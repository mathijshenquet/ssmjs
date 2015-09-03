
if not global?
  global = window


cpu = new SimpleCPU(SSMInstructionSet)

hotswap = ->
  code = Parser.parse(View.getSrc())
  cpu.load(code)

reset = ->
  cpu.reset()
  View.update(cpu)

step = ->
  console.log("step")

  hotswap()
  cpu.step()
  View.update(cpu)

run = ->
  hotswap()
  cpu.run()
  View.update(cpu)

View.addButton "rewind", reset

View.addButton "step-back", ->

View.addButton "step", step

View.addButton "fast-forward", run

$(document).bind('keydown', 'ctrl+]', step);

View.sourceChanged = ->
  hotswap()
  View.update(cpu)

View.sourceChanged()

global._ = {cpu}
