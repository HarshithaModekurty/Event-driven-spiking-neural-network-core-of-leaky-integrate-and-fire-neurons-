"""Fair round-robin arbiter for queued AER input ports."""

from collections import deque
from dataclasses import dataclass
from collections.abc import Iterable


@dataclass(frozen=True)
class AERRequest:
    port: int
    address: int


class RoundRobinAERArbiter:
    """Select one queued address and hold it stable until acknowledged."""

    def __init__(self, num_ports: int) -> None:
        if num_ports <= 0:
            raise ValueError("num_ports must be positive")
        self.queues = [deque() for _ in range(num_ports)]
        self.next_port = 0
        self._held: AERRequest | None = None

    def enqueue(self, port: int, address: int) -> None:
        if not 0 <= port < len(self.queues):
            raise ValueError("port is outside configured range")
        if address < 0:
            raise ValueError("address must be non-negative")
        self.queues[port].append(address)

    def enqueue_many(self, port: int, addresses: Iterable[int]) -> None:
        for address in addresses:
            self.enqueue(port, address)

    def cycle(self, acknowledge: bool = False) -> AERRequest | None:
        """Return the active request; advance/pop only when acknowledged.

        A request selected on this call cannot be acknowledged until the next
        call, modeling a visible request/acknowledge handshake cycle.
        """
        if self._held is None:
            self._held = self._select()
            return self._held

        request = self._held
        if acknowledge:
            self.queues[request.port].popleft()
            self.next_port = (request.port + 1) % len(self.queues)
            self._held = None
            return request
        return request

    def _select(self) -> AERRequest | None:
        for offset in range(len(self.queues)):
            port = (self.next_port + offset) % len(self.queues)
            if self.queues[port]:
                return AERRequest(port, self.queues[port][0])
        return None