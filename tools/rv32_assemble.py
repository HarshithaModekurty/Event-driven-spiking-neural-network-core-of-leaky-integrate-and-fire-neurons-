"""Small two-pass RV32I assembler for the checked-in boot program.

Supports only the instructions used there; rejects unsupported syntax/ranges.
Generated words run on the unmodified upstream PicoRV32, not a Python CPU.
"""
import re


def assemble(source, constants):
    rows=[]; labels={}; pc=0
    for raw in source.splitlines():
        line=raw.split('#')[0].strip()
        if not line: continue
        if line.endswith(':'):
            label=line[:-1]
            if label in labels: raise ValueError('Duplicate label: '+label)
            labels[label]=pc; continue
        op,*tail=line.split(None,1)
        args=[a.strip() for a in tail[0].split(',')] if tail else []
        rows.append((pc,op,args));pc+=8 if op=='li' else 4
    def reg(s):
        if not re.fullmatch(r'x(?:[0-9]|[12][0-9]|3[01])',s): raise ValueError('Bad register: '+s)
        return int(s[1:])
    def value(s): return constants[s] if s in constants else int(s,0)
    def signed(n,bits):
        if not -(1<<(bits-1))<=n<(1<<(bits-1)): raise ValueError(f'Immediate {n} exceeds {bits} bits')
        return n&((1<<bits)-1)
    def immediate(rd,rs,n,f3,opcode=0x13):
        return signed(n,12)<<20|reg(rs)<<15|f3<<12|reg(rd)<<7|opcode
    words=[]
    for pc,op,a in rows:
        if op=='li':
            n=value(a[1])
            if not -(1<<31)<=n<(1<<32): raise ValueError('li exceeds 32 bits')
            n&=0xffffffff; low=n&0xfff; low=low-4096 if low>=2048 else low
            words += [((n-low)&0xfffff000)|reg(a[0])<<7|0x37,immediate(a[0],a[0],low,0)]
        elif op in ('addi','andi','ori','xori'):
            words.append(immediate(a[0],a[1],value(a[2]),{'addi':0,'andi':7,'ori':6,'xori':4}[op]))
        elif op in ('slli','srli'):
            n=value(a[2])
            if not 0<=n<=31: raise ValueError('Invalid shift')
            words.append(immediate(a[0],a[1],n,1 if op=='slli' else 5))
        elif op in ('lw','lbu','sw','sb'):
            match=re.fullmatch(r'([^()]+)\((x\d+)\)',a[1])
            if not match: raise ValueError('Invalid memory operand')
            n=signed(value(match[1]),12); rs=reg(match[2]); r=reg(a[0])
            if op in ('lw','lbu'): words.append(n<<20|rs<<15|(2 if op=='lw' else 4)<<12|r<<7|3)
            else: words.append((n>>5)<<25|r<<20|rs<<15|(2 if op=='sw' else 0)<<12|(n&31)<<7|0x23)
        elif op in ('beq','bne','blt','bltu','bgeu'):
            n=signed(labels[a[2]]-pc,13)
            if n&1: raise ValueError('Misaligned branch')
            f3={'beq':0,'bne':1,'blt':4,'bltu':6,'bgeu':7}[op]
            words.append((n>>12)<<31|((n>>5)&63)<<25|reg(a[1])<<20|reg(a[0])<<15|f3<<12|((n>>1)&15)<<8|((n>>11)&1)<<7|0x63)
        elif op=='j':
            n=signed(labels[a[0]]-pc,21)
            if n&1: raise ValueError('Misaligned jump')
            words.append((n>>20)<<31|((n>>1)&1023)<<21|((n>>11)&1)<<20|((n>>12)&255)<<12|0x6f)
        elif op=='ebreak': words.append(0x00100073)
        else: raise ValueError('Unsupported instruction: '+op)
    return words
