Creates buttons for your consumables in your bags.
If you are a druid in classic, there is an additional form selector that lets you choose what form to enter once you consumed your combat potion (essential for bears)
Should you not want to enter any form after a potion, press alt. (Planning to add keybind options later on, but it's not implemented yet)


It ranks your health potions, mana potions, mana gems, healthstones, drinks/conjured drinks, and provides 1 button for these categories. Should you run out of a certain consumable in a category, the underlying macro will select the next best available.

The drink button will try to use conjured drinks first, then normal drinks. Press ctrl to use normal drinks.

Health potions/Mana potions will try to use location specific ones (like SSC/Tempest keep), then normal ones. Press ctrl to use normal pots.

Since the buttons are macro based, they use names, so I cannot guarantee that the highest talented healthstone will be used first, if u have multiple of the same rank.

Channeled mana potions are separate category from "normal" mana pots.

Added slash commands:
/dom -- prints out a help
/dom kb -- toggles keybind mode
/dom edit -- toggles edit mode

when you turn on edit mode, special green buttons appear, if you drag any of your buttons into one of the green buttons, it will then become a special BoundButton
BoundButtons are only movable while edit mode is on
BoundButtons can have keybinds. Add keybinds to your BoundButtons by turning on keybind mode. You don't need to be in edit mode for keybind mode to work.

 
If you have suggestions, don't hesitate to ask. I know it's very barebones at the moment, but it is functional.

The immediate goal is to add support at least up to Cata consumables.
