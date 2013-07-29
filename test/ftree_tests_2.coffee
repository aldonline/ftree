chai = require 'chai'
should = chai.should()
assert = require 'assert'

rcell = require 'reactive-cell'
ftree = require '../lib'
{sub, exit} = ftree


class TreeWrapper
  constructor: ( f ) ->
    @stack = []
    @tree = ftree f (str) => @stack.push str
    @tree.invalidation_handler = => @stack.push 'INV'
    @tree.error_handler = (e) => @stack.push 'ERR'

  enter:  -> @result = @tree.enter()
  update: -> @tree.update()
  exit:   -> @tree.exit()
  invalid:  -> @tree.invalid()

  expect_result: (v) -> @result.should.equal v
  expect_valid: -> @invalid().should.equal false
  expect_invalid: -> @invalid().should.equal true

  expect: (str)->
    s = @stack.join ' '
    @stack = []
    s.should.equal str


describe 'function tree using tags', ->

  it 'should have an API', ->
    tree = ftree -> 5
    tree.exit.should.be.a 'function'
    tree.enter.should.be.a 'function'
    tree.update.should.be.a 'function'

  it 'should return a simple value', ->
    tree = ftree -> 5
    ret = tree.enter()
    ret.should.equal 5

  it 'should enter and exit a tree', ->
    arr = []
    a = (m) -> arr.push m
    example = ->
      a '>1'
      sub ->
        a '>1.1'
        sub ->
          a '>1.1.1'
          exit -> a '<1.1.1'
        exit -> a '<1.1'
      sub ->
        a '>1.2'
        sub ->
          a '>1.2.1'
          exit -> a '<1.2.1'
        exit -> a '<1.2'
      exit -> a '<1'
      'retval'

    tree = ftree example
    res = tree.enter()
    res.should.equal 'retval'

    a 'M' # we can wait/do stuff before exiting
    tree.exit()

    x = arr.join '\n'

    y = """
    >1
    >1.1
    >1.1.1
    >1.2
    >1.2.1
    M
    <1.2.1
    <1.2
    <1.1.1
    <1.1
    <1"""

    x.should.equal y


  it 'should manage simple reactive functions', ->

    cell = rcell()
    cell 'A'

    t = new TreeWrapper (a) -> ->
      value = cell()
      a '>' + value
      exit -> a '<' + value
      value

    t.enter()
    t.expect_result 'A'
    t.expect '>A' # enter A
    t.expect_valid()

    cell 'B' # we change a value
    t.expect 'INV'
    t.expect_invalid()
       
    # we can change the value again and nothing should happen
    cell 'C'
    t.expect ''  

    # call update...
    t.update()
    
    t.expect '<A >C'
    t.expect_valid()

    # change and update again
    cell 'D'
    t.expect 'INV'
    t.expect_invalid()
    t.update()
    t.expect_valid()
    t.expect '<C >D'

  
  it 'should manage nested reactive functions', ->

    cell_1_1_1 = rcell()
    cell_1_2   = rcell()

    cell_1_1_1 ''
    cell_1_2 ''

    arr = []
    a = (m) -> arr.push m
    expect = (txt) -> txt.should.equal arr.join '\n'

    t = new TreeWrapper (a) -> ->
      a '>1'
      sub ->
        a '>1.1'
        sub ->
          v = '1.1.1' + cell_1_1_1()
          a '>' + v
          exit ->
            a '<' + v
        exit -> a '<1.1'
      sub ->
        v = '1.2' + cell_1_2()
        a '>' + v
        sub ->
          a '>1.2.1'
          exit -> a '<1.2.1'
        exit -> a '<' + v
      exit -> a '<1'
      'retval'

    t.enter()
    t.expect_result 'retval'
    t.expect '>1 >1.1 >1.1.1 >1.2 >1.2.1' # entered all states
    t.expect_valid()

    
    # we change a cell. we should receive an invalidation event
    cell_1_1_1 'A'
    t.expect_invalid()
    t.expect 'INV'

    t.update()
    t.expect  '<1.1.1 >1.1.1A'
    t.expect_valid()

    # change cell again
    cell_1_1_1 'B'
    t.expect 'INV'
    t.expect_invalid()
    # and another cell before updating. nothing should happen
    cell_1_2 'C'
    t.expect ''
    t.expect_invalid()

    # update now
    t.update()
    
    t.expect '<1.1.1A >1.1.1B <1.2.1 <1.2 >1.2C >1.2.1'

