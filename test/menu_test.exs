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

  defp menu, do: Menu.new([{"ONE", :one}, {"TWO", :two}, {"THREE", :three}])

  test "nothing pressed keeps the menu as it is, even with keys held" do
    held = %{pressing(1, []) | 1 => %{pressing(1, [])[1] | held: MapSet.new([:attack])}}
    assert Menu.input(menu(), held) == {:stay, menu()}
  end

  test "up and down move the selection and stop at the ends" do
    {:stay, moved} = Menu.input(menu(), pressing(1, [:down]))
    assert Menu.selected(moved) == :two

    {:stay, top} = Menu.input(menu(), pressing(2, [:up]))
    assert Menu.selected(top) == :one

    bottom = %{menu() | selected: 2}
    assert {:stay, ^bottom} = Menu.input(bottom, pressing(1, [:down]))
  end

  test "a disabled choice is passed over and never selected first" do
    menu = Menu.new([{"OFF", :disabled}, {"ONE", :one}, {"DIM", :disabled}, {"TWO", :two}])
    assert Menu.selected(menu) == :one

    {:stay, moved} = Menu.input(menu, pressing(1, [:down]))
    assert Menu.selected(moved) == :two

    {:stay, back} = Menu.input(moved, pressing(1, [:up]))
    assert Menu.selected(back) == :one
    assert {:stay, ^back} = Menu.input(back, pressing(1, [:up]))
  end

  test "start or attack from either side chooses, and jump goes back, naming the side" do
    assert Menu.input(menu(), pressing(1, [:start])) == {:choose, :one, 1}
    assert Menu.input(%{menu() | selected: 1}, pressing(2, [:attack])) == {:choose, :two, 2}
    assert Menu.input(menu(), pressing(2, [:jump])) == {:back, 2}
  end
end
