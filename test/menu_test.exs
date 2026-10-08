defmodule Nidhox.Screen.MenuTest do
  use ExUnit.Case, async: true

  alias Nidhox.Screen.Menu

  defp pressing(side, keys) do
    none = %{held: MapSet.new(), pressed: MapSet.new(), released: MapSet.new()}

    Map.put(%{1 => none, 2 => none}, side, %{
      none
      | pressed: MapSet.new(keys),
        held: MapSet.new(keys)
    })
  end

  defp menu, do: Menu.new("PICK", [{"ONE", :one}, {"TWO", :two}, {"THREE", :three}])

  test "nothing pressed keeps the menu as it is, even with keys held" do
    held = %{pressing(1, []) | 1 => %{pressing(1, [])[1] | held: MapSet.new([:attack])}}
    assert Menu.input(menu(), held) == {:stay, menu()}
  end

  test "up and down move the selection and stop at the ends" do
    {:stay, moved} = Menu.input(menu(), pressing(1, [:down]))
    assert Menu.selected(moved) == :two

    {:stay, top} = Menu.input(menu(), pressing(2, [:up]))
    assert Menu.selected(top) == :one

    bottom = Menu.new("PICK", menu().choices, 2)
    assert {:stay, ^bottom} = Menu.input(bottom, pressing(1, [:down]))
  end

  test "start or attack from either side chooses, and jump goes back" do
    assert Menu.input(menu(), pressing(1, [:start])) == {:choose, :one}

    assert Menu.input(Menu.new("PICK", menu().choices, 1), pressing(2, [:attack])) ==
             {:choose, :two}

    assert Menu.input(menu(), pressing(1, [:jump])) == :back
  end
end
