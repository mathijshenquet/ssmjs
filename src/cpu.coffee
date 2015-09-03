
if not global?
  global = window

binOp = (op) ->
  fn = new Function("a, b", "return a #{op} b")
  lbl = new Function("a, b", "return '('+a+' #{op} '+b+')';")
  (newLabel) ->
    b = @pop()
    a = @pop()

    value = fn(a.value, b.value)
    label = if a.label? && b.label? && (not newLabel?) then lbl(a.label, b.label) else undefined

    @push value, (newLabel ? label)

binPred = (op) ->
  fn = new Function("a, b", "return (a #{op} b) ? 1 : -1")
  lbl = new Function("a, b", "return '('+a+' #{op} '+b+')';")
  (newLabel) ->
    b = @pop()
    a = @pop()

    value = fn(a.value, b.value)
    label = if a.label? && b.label? && (not newLabel?) then lbl(a.label, b.label) else undefined

    @push value, (newLabel ? label)

global.SSMInstructionSet = {
  add: binOp "+"
  sub: binOp "-"
  mul: binOp "*"
  div: binOp "/"
  mod: binOp "%"

  neg: (newLabel) ->
    {value, label} = @pop();
    @push(-value, "-(#{newLabel ? label})")

  eq: binPred "=="
  ne: binPred "!="
  lt: binPred "<"
  gt: binPred ">"
  le: binPred "<="
  ge: binPred ">="

  or: binOp "|"
  xor: binOp "^"

  not: (newLabel) ->
    {value, label} = @pop()
    @push(value ^ 0xFFFF, "!(#{newLabel ? a.label})")

  ldc: (a, label) ->
    @push(a, label ? a)

  ldr: (regHandle, label) ->
    id = @regId(regHandle)
    @push(@get(id), (label ? @get(id, 'label')))

  str: (regHandle, newLabel) ->
    {value, label} = @pop()
    @set @regId(regHandle), value, (newLabel ? label)

  lds: (n, label) ->
    addr = @r[SP] + n
    @push @read(addr), (label ? @read(addr, 'label'))
    @mem.read[addr] = true;

  sts: (n, newLabel) ->
    {value, label} = @pop()
    @write (@get(SP) + (n+1)), value, (newLabel ? label)

  ldl: (n, newLabel) ->
      @push @read(@get(MP) + n), (newLabel ? @read(@get(MP) + n, 'label'))

  stl: (n, newLabel) ->
      {value, label} = @pop()
      @write (@get(MP) + n), value, (newLabel ? label)

  brt: (addr) -> @jump(addr) if @pop().value == 1
  brf: (addr) -> @jump(addr) if @pop().value != 1
  bra: (addr) -> @jump(addr)
  bsr: (addr) -> @push(@get(PC), "PC return"); @jump(addr)

  link: (n) ->
    @push(@get(MP), "MP return");
    @set(MP, @get(SP))
    for [0...n]
      @push(0)

  unlink: () ->
    @set(SP, @get(MP))
    @set(MP, @pop().value)

  ret: (addr) -> @set(PC, @pop().value);

  ajs: (n) -> @set(SP, @get(SP) + n)

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
    @labels = {}
    @reset()

  reset: ->
    @history = []

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

    @lineNr = @code[@r[PC]]?.lineNr ? false

  write: (addr, value, label) ->
    oldValue = @mem.int[addr];
    oldLabel = @mem.label[addr];
    oldWritten = @mem.written[addr];

    @stateApply
      do: ->
        @mem.int[addr] = value;
        @mem.written[addr] = true;

        if label?
          @mem.label[addr] = label;

      undo: ->
        @mem.int[addr] = oldValue
        @mem.written[addr] = oldWritten;
        @mem.label[addr] = oldLabel;

  read: (addr, type) -> @stateApply
    do: ->
      @mem.read[addr] = true
      @mem[type ? 'int'][addr]

    undo: ->

  set: (n, value, label) ->
    oldValue = @reg.int[n];
    oldLabel = @reg.label[n];
    oldWritten = @reg.written[n];

    @stateApply
      do: ->
        @reg.int[n] = value
        @reg.written[n] = true

        if label?
          @reg.label[n] = label

      undo: ->
        @reg.int[n] = oldValue
        @reg.written[n] = oldWritten;
        @reg.label[n] = oldLabel;

  get: (n, type) -> @stateApply
    do: ->
      @reg.read[n] = true
      @reg[type ? 'int'][n]

    undo: ->

  jump: (addr) ->
    oldPC = @r[PC];
    oldLineNr = @lineNr

    @stateApply
      do: ->
        @r[PC] = @labels[addr];
        @lineNr = @code[@r[PC]]?.lineNr ? false

      undo: ->
        @r[PC] = oldPC;
        @lineNr = oldLineNr;

  pop: ->
    @stateApply
      do: ->
        {value: @read(@r[SP]), label: @mem.label[@r[SP]--]}

      undo: ->
        @r[SP]++

  push: (value, label) ->
    oldMemSeen = @memSeen

    @stateApply
      do: ->
        @write(++@r[SP], value, label)
        @memSeen = Math.max(@memSeen, @r[SP])

      undo: ->
        @r[SP]--
        @memSeen = oldMemSeen


  peek: -> @stateApply
    do: ->
      @read(@r[SP])
    undo: ->

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

  stateApply: (cmd) ->
    @stepObject.stateActions.push(cmd)
    cmd.do.call(this)

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

    @stepObject = {
      oldPC: @r[PC],
      stateActions: []
    }

    instruction = @code[@r[PC]++]
    if not instruction?
      @lineNr = false
      @r[PC]--;
      return false;


    @exec(instruction)
    @history.push(@stepObject)

    @lineNr = @code[@r[PC]]?.lineNr
    return true;

  undo: ->
    if not stepObject = @history.pop()
      return;

    while action = stepObject.stateActions.pop()
      action.undo.call(this)
    @r[PC] = stepObject.oldPC;
    @lineNr = @code[@r[PC]]?.lineNr

  exec: (instruction) ->
    unless @instructions[instruction.opcode]?
      throw new Error("Unknown opcode #{instruction.opcode}")

    args = [].concat(instruction.args, instruction.hint.label)
    @instructions[instruction.opcode].apply(this, args)

    return;
