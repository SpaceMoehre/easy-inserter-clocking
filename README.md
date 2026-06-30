# Easy Inserter Clocking

A small **Factorio 2.0** mod that makes inserter clocking easy.

Instead of hand-building combinator clocks every time you need an inserter to
move items at a precise, throttled rate, you tell the mod **which item**, **how
many of it**, and **over what timeframe** — and it generates a ready-to-place
combinator blueprint straight into your cursor.

## What is inserter clocking?

A clocked inserter is gated by the circuit network so it only swings on a fixed
schedule, letting you dial in an exact average throughput (e.g. *1 item every
0.5 s*) rather than running at full speed. It's handy for feeding reactors,
balancing trickle inputs, and any ratio that needs to be exact.

## Usage

1. Click the **`EIC`** button in the top-left mod button row to open the panel.
2. Fill in:
   - **Target Item** – the item the inserter moves.
   - **Items** / **Every (seconds)** – the rate, e.g. `1` item every `0.5` s.
   - **Stack size** – how many items the inserter grabs per swing (its hand size).
   - **Pickup from belt** – check this when grabbing off a belt (uses a longer
     enable window so the hand fills); leave unchecked for chest-to-chest.
3. Click **Create Blueprint**. A 3-combinator clock appears in your cursor.
4. Place it, then wire the **decider combinator's green output** to your
   inserter, set the inserter to **Enable/disable**, and set its hand stack
   size to match the value you entered.

## How the blueprint works

The generated blueprint is a self-resetting clock on signal `C`:

| # | Combinator | Role |
|---|------------|------|
| 1 | Constant   | Emits `+increment` per tick on signal `C`. |
| 2 | Arithmetic | `C % modulo`, output looped back to its own input — a sawtooth counter. |
| 3 | Decider    | Emits the chosen item signal while `C <= window` — the inserter's enable pulse. |

With fixed-point math (`×100` for sub-tick precision):

```
rate      = items / timeframe          (items per second)
increment = floor(rate × 100)
modulo    = stack × 60 × 100           (60 ticks per second)
period    = modulo / increment ticks  =  stack / rate  seconds
```

The inserter activates once per `period`, grabbing `stack` items, which averages
out to exactly `rate` items per second.

> **Note:** this controls *average throughput*, not the timing of individual
> swings — the inserter grabs a full hand every few seconds rather than one item
> on every tick of your timeframe.

## Installation (from source)

Factorio loads an unzipped mod only when its folder is named exactly after the
mod, so clone or symlink it as `easy-inserter-clocking`:

```
git clone git@github.com:SpaceMoehre/easy-inserter-clocking.git \
  ~/.factorio/mods/easy-inserter-clocking
```

Then enable **Easy Inserter Clocking** in the in-game Mods menu and restart.

## License

See [LICENSE](LICENSE).
