# Cask de CmdDock. Se publica en el tap Crisdotcom/homebrew-tap (Casks/cmddock.rb):
#   brew install --cask crisdotcom/tap/cmddock
# El workflow de release actualiza `version` y `sha256` automáticamente (scripts/update-cask.sh).
cask "cmddock" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/Crisdotcom/CmdDock/releases/download/v#{version}/CmdDock-#{version}.zip"
  name "CmdDock"
  desc "Spotlight-style launcher for your saved terminal commands"
  homepage "https://github.com/Crisdotcom/CmdDock"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "CmdDock.app"
  binary "#{appdir}/CmdDock.app/Contents/MacOS/CmdDock", target: "cmddock"

  postflight do
    # La app está firmada ad-hoc (no notarizada): se quita la cuarentena para que
    # Gatekeeper permita abrirla.
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/CmdDock.app"]
    # Abre CmdDock: la primera vez pregunta si quieres analizar tu historial de comandos
    # para proponerte grupos (se puede omitir).
    system_command "/usr/bin/open", args: ["#{appdir}/CmdDock.app"]
  end

  uninstall quit:       "io.github.crisdotcom.CmdDock",
            login_item: "CmdDock"

  zap trash: [
    "~/Library/Application Support/CmdDock",
    "~/Library/Preferences/io.github.crisdotcom.CmdDock.plist",
  ]

  caveats <<~EOS
    CmdDock se ha abierto: si es la primera vez, te preguntará si quieres analizar
    tu historial de comandos para proponerte grupos (puedes omitirlo).

    Ábrelo cuando quieras con ⌥⌘K (personalizable en Ajustes).

    Para enviar comandos a Warp o Ghostty necesita permiso de Accesibilidad:
      Ajustes del Sistema → Privacidad y seguridad → Accesibilidad → CmdDock

    Desde la terminal:
      cmddock scan            # propone grupos a partir de tu historial
      cmddock scan --apply    # los añade
  EOS
end
