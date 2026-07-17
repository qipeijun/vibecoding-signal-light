"""Lamp language patterns for AI agent state."""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Protocol


class LightWriter(Protocol):
    def write(self, *, green: bool = False, yellow: bool = False, red: bool = False) -> None:
        ...

    def off(self) -> None:
        ...


class BrightnessWriter(Protocol):
    def write_brightness(self, *, green: float = 0.0, yellow: float = 0.0, red: float = 0.0) -> None:
        ...


@dataclass(frozen=True)
class Frame:
    green: bool = False
    yellow: bool = False
    red: bool = False
    seconds: float = 0.2
    brightness: float = 1.0


@dataclass(frozen=True)
class AgentSignal:
    name: str
    summary: str
    attention: str
    frames: tuple[Frame, ...]
    loops: int = 1
    leave_on: tuple[bool, bool, bool] | None = None
    repeat: bool = False

    def play(self, light: LightWriter, speed: float = 1.0, cycles: int | None = None) -> None:
        delay_scale = max(speed, 0.05)
        for _ in range(cycles if cycles is not None else self.loops):
            for frame in self.frames:
                _play_frame(light, frame, delay_scale)

        if self.leave_on is None:
            light.off()
            return

        green, yellow, red = self.leave_on
        light.write(green=green, yellow=yellow, red=red)

    def play_forever(self, light: LightWriter, speed: float = 1.0) -> None:
        delay_scale = max(speed, 0.05)
        while True:
            for frame in self.frames:
                _play_frame(light, frame, delay_scale)


def _play_frame(light: LightWriter, frame: Frame, delay_scale: float) -> None:
    duration = max(frame.seconds * delay_scale, 0.0)
    brightness = _clamp_brightness(frame.brightness)
    target_on = frame.green or frame.yellow or frame.red

    if not target_on or brightness <= 0.0:
        light.off()
        time.sleep(duration)
        return

    if brightness >= 1.0:
        light.write(green=frame.green, yellow=frame.yellow, red=frame.red)
        time.sleep(duration)
        return

    write_brightness = getattr(light, "write_brightness", None)
    if callable(write_brightness):
        write_brightness(
            green=brightness if frame.green else 0.0,
            yellow=brightness if frame.yellow else 0.0,
            red=brightness if frame.red else 0.0,
        )
        time.sleep(duration)
        return

    light.write(green=frame.green, yellow=frame.yellow, red=frame.red)
    time.sleep(duration)


def _clamp_brightness(value: float) -> float:
    return max(0.0, min(1.0, value))


def _solid(
    green: bool = False,
    yellow: bool = False,
    red: bool = False,
    seconds: float = 0.4,
) -> Frame:
    return Frame(green=green, yellow=yellow, red=red, seconds=seconds)


def _state(
    green: bool = False,
    yellow: bool = False,
    red: bool = False,
) -> tuple[tuple[Frame, ...], tuple[bool, bool, bool]]:
    return (), (green, yellow, red)


def _flash(green: bool = False, yellow: bool = False, red: bool = False) -> tuple[Frame, Frame]:
    return (
        Frame(green=green, yellow=yellow, red=red, seconds=0.30),
        Frame(seconds=0.70),
    )


def _work_pulse() -> tuple[Frame, ...]:
    return _pulse(green=True, period=2.0)


def _pulse(
    *,
    green: bool = False,
    yellow: bool = False,
    red: bool = False,
    period: float,
) -> tuple[Frame, ...]:
    # 从峰值开始，按余弦呼吸曲线取样；25% 谷值避免长期状态看起来像熄灭。
    brightness_levels = (1.0, 0.93, 0.74, 0.48, 0.32, 0.25, 0.32, 0.48, 0.74, 0.93)
    return tuple(
        Frame(
            green=green,
            yellow=yellow,
            red=red,
            seconds=period / len(brightness_levels),
            brightness=brightness,
        )
        for brightness in brightness_levels
    )


def _double_flash(*, green: bool = False, red: bool = False) -> tuple[Frame, ...]:
    return (
        Frame(green=green, red=red, seconds=0.18),
        Frame(seconds=0.18),
        Frame(green=green, red=red, seconds=0.18),
        Frame(seconds=1.46),
    )


SIGNALS: dict[str, AgentSignal] = {
    "idle": AgentSignal(
        name="idle",
        summary="Agent 空闲。",
        attention="不需要关注。",
        frames=_state(green=True)[0],
        leave_on=_state(green=True)[1],
    ),
    "thinking": AgentSignal(
        name="thinking",
        summary="Agent 已收到任务，正在思考、工作或输出内容。",
        attention="不用处理。",
        frames=_work_pulse(),
        repeat=True,
    ),
    "working": AgentSignal(
        name="working",
        summary="Agent 正在执行工具、读写文件、跑命令、测试或输出内容。",
        attention="不用处理。",
        frames=_work_pulse(),
        repeat=True,
    ),
    "tool_done": AgentSignal(
        name="tool_done",
        summary="一次工具调用完成，Agent 仍处于工作流中。",
        attention="不用处理。",
        frames=_work_pulse(),
        repeat=True,
    ),
    "attention": AgentSignal(
        name="attention",
        summary="Agent 停下来等你读结果或继续回复。",
        attention="需要你看一眼 Codex。",
        frames=_flash(yellow=True),
        loops=8,
        repeat=True,
    ),
    "permission": AgentSignal(
        name="permission",
        summary="Codex 请求授权或需要你明确批准。",
        attention="需要立即关注。",
        frames=_pulse(red=True, period=2.0),
        repeat=True,
    ),
    "blocked": AgentSignal(
        name="blocked",
        summary="Agent 遇到阻塞、失败或无法继续。",
        attention="需要你处理。",
        frames=_double_flash(red=True),
        loops=12,
        repeat=True,
    ),
    "done": AgentSignal(
        name="done",
        summary="任务已完成。",
        attention="不需要关注。",
        frames=_double_flash(green=True),
        leave_on=_state(green=True)[1],
    ),
    "session_start": AgentSignal(
        name="session_start",
        summary="Codex 会话开始。",
        attention="不用处理。",
        frames=_state(green=True)[0],
        leave_on=_state(green=True)[1],
    ),
    "session_end": AgentSignal(
        name="session_end",
        summary="Codex 会话结束，回到空闲状态。",
        attention="不需要关注。",
        frames=_state(green=True)[0],
        leave_on=_state(green=True)[1],
    ),
    "stale": AgentSignal(
        name="stale",
        summary="最近状态已超过租约，当前真实状态无法确认。",
        attention="建议检查 Agent 或 hook 是否仍在运行。",
        frames=_pulse(yellow=True, period=2.8),
        repeat=True,
    ),
    "off": AgentSignal(
        name="off",
        summary="关闭所有灯。",
        attention="不需要关注。",
        frames=(Frame(seconds=0.01),),
    ),
}
