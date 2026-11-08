"""Text serialization for spike rasters sent to a UART console."""

from collections.abc import Iterable


def format_spike_raster(ticks: Iterable[Iterable[int]]) -> str:
    """Format each tick as ``tick,address[,address...]`` records.

    Empty ticks are omitted. The returned string ends with a newline when it
    contains at least one event, making it suitable for line-oriented UART TX.
    """
    lines = []
    for tick, addresses in enumerate(ticks):
        for address in sorted(addresses):
            if address < 0:
                raise ValueError("spike addresses must be non-negative")
            lines.append(f"{tick},{address}")
    return "\n".join(lines) + ("\n" if lines else "")