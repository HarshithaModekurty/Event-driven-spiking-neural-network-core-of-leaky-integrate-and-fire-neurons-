# RV32I boot/inference program. No stack, runtime, compressed or M instructions.
# x10: peripheral base; x11: weight destination; x12: packed-weight pointer
# x18: image pointer; x19: expected prediction pointer; x20: result pointer
# x21: images left; x22: ticks left; x23: state index
# x24: best score; x25: predicted class; x26: first output state (246)
# Constants are supplied by tools/run_rv32_check.py. li always emits LUI+ADDI.
    li x10, 0x40000000
    lw x5, 0(x10)
    li x6, 0x534e4e32
    bne x5, x6, fail
    li x11, 0x40001000
    li x12, 0x1000
    li x13, 32768
weights:
    lbu x5, 0(x12)
    andi x6, x5, 15
    sw x6, 0(x11)
    srli x6, x5, 4
    sw x6, 4(x11)
    addi x11, x11, 8
    addi x12, x12, 1
    addi x13, x13, -1
    bne x13, x0, weights
    li x5, THRESHOLD
    sw x5, 16(x10)
    li x5, RESET_VALUE
    sw x5, 20(x10)
    li x5, LEAK_CONFIG
    sw x5, 24(x10)
    li x5, REFRACTORY_PERIOD
    sw x5, 28(x10)
    li x18, 0x9000
    li x19, 0xb000
    li x20, 0xc000
    li x21, IMAGES
    li x26, 246
image:
    addi x5, x0, 2
    sw x5, 4(x10)
    li x11, 0x40080000
    li x13, 256
intensities:
    lbu x5, 0(x18)
    sw x5, 0(x11)
    addi x18, x18, 1
    addi x11, x11, 4
    addi x13, x13, -1
    bne x13, x0, intensities
    addi x22, x0, 8
tick:
    addi x5, x0, 1
    sw x5, 4(x10)
packet:
    lw x5, 40(x10)
    blt x5, x0, valid
    j packet
valid:
    andi x6, x5, 256
    beq x6, x0, packet
idle:
    lw x5, 8(x10)
    andi x5, x5, 1
    bne x5, x0, idle
    addi x23, x0, 0
    addi x24, x0, 0
    addi x25, x0, 0
states:
    sw x23, 32(x10)
    lw x5, 36(x10)
    bltu x23, x26, next_state
    slli x5, x5, 16
    srli x5, x5, 16
    bgeu x24, x5, next_state
    addi x24, x5, 0
    addi x25, x23, -246
next_state:
    addi x23, x23, 1
    li x5, 256
    bne x23, x5, states
    addi x22, x22, -1
    bne x22, x0, tick
    sw x25, 0(x20)
    lw x5, 0(x19)
    bne x25, x5, fail
    addi x19, x19, 4
    addi x20, x20, 4
    addi x21, x21, -1
    bne x21, x0, image
    li x5, 0x600d600d
    sw x5, 68(x10)
    ebreak
fail:
    li x5, 0xdead0001
    sw x5, 68(x10)
    ebreak
