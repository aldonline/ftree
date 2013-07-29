reactivity = require 'reactivity'

###
tree = build func
tree.error_handler = (e) -> console.log e
tree.invalidation_handler = -> console.log 'invalid. you should update now to exit and enter only affected nodes'
tree.update()
tree.enter()
tree.exit()
tree.invalid():Boolean
###
module.exports = X = ( func ) ->
  api = {}
  root_block = new Block null, func
  root_block.error_handler        = (e) -> api.error_handler? e
  root_block.invalidation_handler =     -> api.invalidation_handler?()
  
  # export minimal API
  api.enter   = -> root_block.enter()
  api.update  = -> root_block.update()
  api.exit    = -> root_block.exit()
  api.invalid = -> root_block.descendant_invalid or root_block.invalid

  api

stack = []
current = -> stack[stack.length - 1]
X.sub = (f) -> current()._ctx().sub f
X.exit = (f) -> current()._ctx().exit f
X.invalidator = -> b = current() ; -> b._ctx().invalidate()


class Block
  invalid: no
  descendant_invalid: no
  constructor: ( @parent, @func ) ->

  # this is the API that we expose to the users of this library
  _ctx: -> @__ctx ?= do =>
    sub:    (f) => b = new Block @, f ; @children.push b ; b.enter()
    exit:   (f) => @exit_handler = f
    invalidate: => @invalidate_by_func()      

  enter: ->
    @invalid = no
    @descendant_invalid = no
    # will be populated when running the function ( by calling @sub(f) )
    @children = []
    # will be set when running the function
    @exit_handler = null

    # push, run, pop
    stack.push @
    {result, error, monitor} = reactivity => @func.apply @_ctx(), null 
    stack.pop()

    if error?   then @bubble_error error
    if monitor? then (@monitor = monitor).onChange @invalidate_by_monitor
    result

  _invalidate: (bubble = no) ->
    @invalid = yes
    # 1. destroy monitor
    @monitor?.destroy()
    # 2. invalidate children
    c.invalidate_by_parent() for c in @children
    # 3. notify parent
    @bubble_invalidation() if bubble

  # the same function ( state ) decides to invalidate itself
  invalidate_by_func:    => @_invalidate yes
  
  # a reactive monitor requests invalidation
  # ( from a reactive function called inside the block )
  invalidate_by_monitor: => @_invalidate yes

  # a parent block was invalidated and it commands all
  # downstream blocks to invalidate
  invalidate_by_parent:  => @_invalidate no
  

  bubble_invalidation: =>
    return if @descendant_invalid
    @descendant_invalid = yes
    @invalidation_handler?()
    @parent?.bubble_invalidation?()

  bubble_error:    (e) =>
    @parent?.bubble_error? e
    @error_handler? e


  update: =>
    if @invalid
      @exit yes
      @enter()
    else if @descendant_invalid # propagate downstream
      c.update() for c in @children
    # reset both flags
    @invalid = no
    @descendant_invalid = no
  
  # origin = yes when this is topmost node exiting
  exit: (we_are_the_topmost_exiting_node = no) ->
    # exit our children in reverse order
    ( cs = @children.concat() ).reverse()
    c.exit() for c in cs
    # exit self if a handler was specified
    @exit_handler? we_are_the_topmost_exiting_node # the flag may be useful for optimization
    delete @exit_handler
    delete @children



