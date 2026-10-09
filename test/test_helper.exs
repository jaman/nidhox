case Nidhox.Assets.find(nil) do
  nil ->
    ExUnit.start(exclude: [:copy])

  path ->
    {:ok, _assets} = Nidhox.Assets.load(path)
    ExUnit.start()
end
