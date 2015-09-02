
if not global?
  global = window


cpu = new SimpleCPU(SSMInstructionSet)

hotswap = ->
  code = Parser.parse(View.getSrc())
  cpu.load(code)

reset = -> cpu.reset()

View.addButton "reset",   ->
  cpu.reset();
  View.update(cpu)

View.addButton "step",   ->
  hotswap()

  cpu.step()
  View.update(cpu)
  #View.print(cpu.mem.join("\n"))

View.addButton "run",  ->
  hotswap()

  cpu.run()
  View.update(cpu)
  #View.print(cpu.mem.join("\n"))

View.sourceChanged = ->
  hotswap()
  View.update(cpu)

View.sourceChanged()

global._ = {cpu}