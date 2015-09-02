
if not global?
  global = window

binOp = (op) ->
  fn = new Function("a, b", "return a #{op} b")
  lbl = new Function("a, b", "return '('+a+' #{op} '+b+')';")
  {
    label: (newLabel) ->
      b = @popCmt()
      a = @popCmt()

      value = fn(a.value, b.value)
      label = if a.label? && b.label? && (not newLabel?) then lbl(a.label, b.label) else undefined

      @push value, (newLabel ? label)

    normal: ->
      b = @pop()
      a = @pop()
      @push fn(a, b)
  }

binPred = (op) ->
  fn = new Function("a, b", "return (a #{op} b) ? 1 : -1")
  lbl = new Function("a, b", "return '('+a+' #{op} '+b+')';")
  {
    label: (newLabel) ->
      b = @popCmt()
      a = @popCmt()

      value = fn(a.value, b.value)
      label = if a.label? && b.label? && (not newLabel?) then lbl(a.label, b.label) else undefined

      @push value, (newLabel ? label)

    normal: ->
      b = @pop()
      a = @pop()
      @push fn(a, b)
  }

global.SSMInstructionSet = {
  add: binOp "+"
  sub: binOp "-"
  mul: binOp "*"
  div: binOp "/"
  mod: binOp "%"

  neg: {
    normal: -> @push(-@pop())
    label: (newLabel) ->
      {value, label} = @popCmt();
      @push(-value, "-(#{newLabel ? label})")
  }

  eq: binPred "=="
  ne: binPred "!="
  lt: binPred "<"
  gt: binPred ">"
  le: binPred "<="
  ge: binPred ">="

  or: binOp "|"
  xor: binOp "^"

  not:
    normal: -> @push(@pop() ^ 0xFFFF)
    label: (newLabel) ->
      {value, label}
      @push(value ^ 0xFFFF, "!(#{newLabel ? a.label})")

  ldc:
    normal: (a) ->
      @push(a)
    label: (a, newLabel) ->
      @push(a, newLabel ? a)

  ldr:
    normal: (regHandle) ->
      id = @regId(regHandle)
      @push(@reg.int[id])
    label: (regHandle, newLabel) ->
      id = @regId(regHandle)
      @push(@reg.int[id], (newLabel ? @reg.label[id]))
      @reg.read[id] = true;
  str:
    normal: (regHandle) ->
      @reg.int[@regId(regHandle)] = @pop()
    label: (regHandle, newLabel) ->
      {value, label} = @popCmt()
      @set @regId(regHandle), value, (newLabel ? label)

  lds:
    normal: (n) ->
      @mem.read[@r[SP] + n] = true;
    label: (n, newLabel) ->
      addr = @r[SP] + n
      @push(@read(addr), (newLabel ? @mem.label[addr]))
      @mem.read[addr] = true;
  sts:
    normal: (n) ->
      value = @pop()
      @write (@r[SP] + (n+1)), value
    label: (n, newLabel) ->
      {value, label} = @popCmt()
      @write (@r[SP] + (n+1)), value, (newLabel ? label)

  ldl:
    normal: (n) ->
      @push(@read(@r[MP] + n))
    label: (n, newLabel) ->
      @push(@read(@r[MP] + n), (newLabel ? @mem.label[@r[MP] + n]))
      @mem.read[@r[MP] + n] = true;
  stl:
    normal: (n) ->
      value = @pop()
      @write (@r[MP] + n), value
    label: (n, newLabel) ->
      {value, label} = @popCmt()
      @write (@r[MP] + n), value, (newLabel ? label)

  brt: (addr) -> @jump(addr) if @pop() == 1
  brf: (addr) -> @jump(addr) if @pop() != 1
  bra: (addr) -> @jump(addr)
  bsr: (addr) -> @push(@r[PC], "PC return"); @jump(addr)

  link: (n) ->
    @push(@r[MP], "MP return");
    @r[MP] = @r[SP];
    for [0...n]
      @push(0)

  unlink: () ->
    @r[SP] = @r[MP]
    @r[MP] = @pop()

  ret: (addr) -> @r[PC] = @pop();

  ajs: (n) -> @r[SP] += n

  halt: -> @halted = true

  annote: (regHandle, low, high, color, text) ->
    console.log regHandle
    reg = @regId(regHandle)
    console.log(@r[reg], low, high, color, text)
    for i in [(@r[reg]+low)..(@r[reg]+high)]
      console.log(i)
      @mem.annote[i] = {color, text}

  nop: ->

  trap: (n) ->
    [
      (=> View.print(@peek()))
    ][n]()

}

PC = 0
SP = 1
MP = 2
HP = 3
RR = 4

class MemoryBank
  constructor: (length) ->
    @buffer = buffer = new ArrayBuffer(length)

    @f64 = new Float64Array(buffer)

    @u32 = new Uint32Array(buffer)
    @i32 = new Int32Array(buffer)
    @f32 = new Float32Array(buffer)

    @u16 = new Uint16Array(buffer)
    @i16 = new Int16Array(buffer)

    @u8 = new Uint8Array(buffer)
    @i8 = new Int8Array(buffer)

    @annote = {}
    @label = {}

    @written = {}
    @read = {}

    @raw = @u32
    @int = @i32
    @float = @f32

class global.SimpleCPU
  constructor: (@instructions) ->
    @code = []
    @labels = true
    @reset()

  reset: ->
    @memSize = 1024
    @memSeen = -1

    @mem = new MemoryBank(4 * @memSize)

    @regCount = 8

    @reg = new MemoryBank(4 * @regCount)
    @r = @reg.int

    @r[PC] = 0
    @r[SP] = -1
    @r[MP] = -1
    @r[HP] = -1

    @halted = false

    @setLineNr()

  setLineNr: ->
    @lineNr = @code[@r[PC]]?.lineNr ? false

  write: (addr, value, label) ->
    @mem.int[addr]   = value;
    @mem.label[addr] = label;
    @mem.written[addr] = true;

  read: (addr) ->
    @mem.int[addr]

  jump: (addr) ->
    @r[PC] = @labels[addr];
    @lineNr = @code[@r[PC]]?.lineNr ? false

  pop: ->
    @read(@r[SP]--)

  popCmt: ->
    {value: @read(@r[SP]), label: @mem.label[@r[SP]--]}

  push: (value, label) ->
    @write(++@r[SP], value, label)
    @memSeen = Math.max(@memSeen, @r[SP])

  peek: -> @read(@r[SP])

  set: (n, value, label) ->
    @reg.int[n] = value;
    @reg.label[n] = label;
    @reg.written[n] = true

  regId: (handle) -> {
    pc: PC
    sp: SP
    mp: MP
    hp: HP
    rr: RR
  }[(new String(handle)).toLowerCase()] ? handle

  regName: (id) -> ["pc", "sp", "mp", "hp", "rr"][id]?.toUpperCase()

  regVal: (selector) ->
    if +selector == selector
      id = selector
    else
      id = @regId(selector)

    return @r[id]

  get: (n) -> @r[n]

  load: (@code) ->
    @lineNr = @code[@r[PC]]?.lineNr
    @labels = {}

    addr = 0
    for instruction in @code
      if instruction.label
        @labels[instruction.label] = addr
      addr++

  run: ->
    while @step() == true
      continue;
    @mem.read = {}
    @mem.written = {}
    @reg.read = {}
    @reg.written = {}
    true

  step: ->
    if @halted
      return false

    instruction = @code[@r[PC]++]
    if not instruction?
      @lineNr = false
      @r[PC]--;
      return false;

    @exec(instruction)
    @lineNr = @code[@r[PC]]?.lineNr
    return true;

  exec: (instruction) ->
    unless @instructions[instruction.opcode]?
      throw new Error("Unknown opcode #{instruction.opcode}")

    tmp = @instructions[instruction.opcode]

    if @labels
      args = [].concat(instruction.args, instruction.hint.label)
      (tmp.label ? tmp).apply(this, args)

    else
      (tmp.normal ? tmp).apply(this, instruction.args)

    return;