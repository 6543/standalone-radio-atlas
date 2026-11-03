{
  lib,
  stdenvNoCC,
  makeWrapper,
  makeDesktopItem,
  writeText,
  copyDesktopItems,
  quickshell,
  python3,
  bash,
  bubblewrap,
  coreutils,
  curl,
  file,
  findutils,
  fontconfig,
  gawk,
  getent,
  glib,
  gnugrep,
  gnused,
  iproute2,
  jq,
  mpv,
  nerd-fonts,
  pulseaudio,
  socat,
  util-linux,
  wl-clipboard,
}:

let
  manifest = lib.importJSON ../manifest.json;

  # radio-mpris needs D-Bus and GLib bindings; the other helpers are stdlib only.
  python = python3.withPackages (ps: [
    ps.dbus-python
    ps.pygobject3
  ]);

  runtimePath = lib.makeBinPath [
    quickshell
    python
    bash
    bubblewrap
    coreutils
    curl
    file
    findutils
    gawk
    getent
    gnugrep
    gnused
    iproute2
    jq
    mpv
    pulseaudio # pactl for the audio output picker
    socat
    util-linux # flock, setpriv, setsid
    wl-clipboard
  ];

  # Omarchy's system font is a Nerd Font, so upstream draws its icons as Font
  # Awesome codepoints. Layer a symbols-only font over the system fontconfig
  # so the icons render with any "monospace" font.
  fontsConf = writeText "radio-atlas-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
      <dir>${nerd-fonts.symbols-only}/share/fonts</dir>
    </fontconfig>
  '';

  appFiles = [
    "RadioAtlas.qml"
    "Globe.qml"
    "RadioModel.js"
    "radio-favicon"
    "radio-fetch"
    "radio-mpris"
    "radio-player"
    "radio-proxy"
    "radio-sandbox"
    "radio-session"
    "radio-state"
    "radio-status.lua"
  ];
in
stdenvNoCC.mkDerivation {
  pname = "radio-atlas";
  inherit (manifest) version;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions (
      map (name: ../. + "/${name}") appFiles
      ++ [
        ../assets
        ../standalone
        ../LICENSE
      ]
    );
  };

  nativeBuildInputs = [
    makeWrapper
    copyDesktopItems
  ];
  # patchShebangs resolves `#!/usr/bin/env python3|bash` against these.
  buildInputs = [
    python
    bash
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    app=$out/share/radio-atlas
    mkdir -p "$app" "$out/bin"
    cp -r ${lib.escapeShellArgs appFiles} assets "$app"/
    cp -r standalone/shell.qml standalone/Commons standalone/Ui "$app"/
    install -Dm644 LICENSE "$out/share/licenses/radio-atlas/LICENSE"
    install -Dm644 standalone/LICENSE.omarchy "$out/share/licenses/radio-atlas/LICENSE.omarchy"

    # Upstream pins FHS interpreters so a shadowed PATH python cannot break
    # MPRIS; pin the store equivalents instead.
    substituteInPlace "$app/radio-mpris" \
      --replace-fail '#!/usr/bin/python3' '#!${lib.getExe python}'
    substituteInPlace "$app/radio-session" \
      --replace-fail '/usr/bin/python3' '${lib.getExe python}' \
      --replace-fail '/usr/bin/bash' '${lib.getExe bash}'
    substituteInPlace "$app/radio-proxy" \
      --replace-fail '"/usr/bin/ip"' '"${lib.getExe' iproute2 "ip"}"'

    install -Dm755 standalone/radio-atlas "$out/bin/radio-atlas"
    wrapProgram "$out/bin/radio-atlas" \
      --set RADIO_ATLAS_DIR "$app" \
      --prefix PATH : ${runtimePath} \
      --prefix GI_TYPELIB_PATH : ${glib.out}/lib/girepository-1.0 \
      --set-default FONTCONFIG_FILE ${fontsConf}

    runHook postInstall
  '';

  # Runs after fixupPhase has patched the remaining shebangs.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    if grep -rnE '/usr/bin/[a-z]' "$out/share/radio-atlas" "$out/bin"; then
      echo "FHS paths left in the package" >&2
      exit 1
    fi
    # Player and window icons are Font Awesome codepoints (U+F04B is "play").
    fonts_conf=$(sed -n "s/^export FONTCONFIG_FILE=\''${FONTCONFIG_FILE-'\(.*\)'}$/\1/p" "$out/bin/radio-atlas")
    if [[ -z $fonts_conf ]] || [[ -z $(FONTCONFIG_FILE=$fonts_conf HOME=$TMPDIR ${lib.getExe' fontconfig "fc-list"} ':charset=f04b' family) ]]; then
      echo "No font for the icon glyphs" >&2
      exit 1
    fi
    runHook postInstallCheck
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "radio-atlas";
      desktopName = "Radio Atlas";
      comment = manifest.description;
      exec = "radio-atlas";
      icon = "audio-x-generic";
      categories = [
        "AudioVideo"
        "Audio"
        "Player"
      ];
      keywords = manifest.keywords;
    })
  ];

  meta = {
    description = "Explore live radio on a rotatable globe (standalone Quickshell app)";
    homepage = manifest.homepage;
    license = lib.licenses.mit;
    mainProgram = "radio-atlas";
    platforms = lib.platforms.linux;
  };
}
