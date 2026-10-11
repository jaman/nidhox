import Config

installs =
  Enum.map(
    [
      "Library/Application Support/CrossOver/Bottles/Steam/drive_c/Program Files (x86)/Steam/steamapps/common/Nidhogg/data.win",
      "Library/Application Support/Steam/steamapps/common/Nidhogg/Nidhogg.app/Contents/Resources/game.ios",
      ".steam/steam/steamapps/common/Nidhogg/data.win",
      ".local/share/Steam/steamapps/common/Nidhogg/data.win"
    ],
    &Path.join(System.user_home!(), &1)
  )

config :nidhox, data: System.get_env("NIDHOX_DATA") || Enum.find(installs, &File.exists?/1)
