require "test_helper"
require "trailblazer/activity/dsl"

# FIXME: encapsulate? but should we really add more code for this?
[
  # Trailblazer::Activity::Path,
  Trailblazer::Activity::Railway,
  # Trailblazer::Activity::FastTrack
].each do |topology|
  _, _, builder, helpers_module = Trailblazer::Activity::DSL::Topology.build(
    builder: topology.config.builder,
    default_options: {},
    **Trailblazer::Activity::VariableMapping::TOPOLOGY_BUILD_OPTIONS # :helpers and :adds
  )

  topology.config.builder = builder
  topology.include helpers_module
end

# Test I/O in {Topology}.
class ActivityIntegrationTest < Minitest::Spec
  # FIXME: stolen from dsl_test.rb.
  def self.my_capture_step(ctx, pollute: false, **kws)
    ctx[:captured] = [ctx.to_h.inspect, kws.inspect]

    ctx[:pollute] = 1 if pollute

    true
  end

  my_capture_step = method(:my_capture_step)

  it "step only sees what is configured via In()" do
    my_railway = Class.new(Trailblazer::Activity::Railway) do
      step my_capture_step,
        In() => [:model, :params]
    end

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success
    # the {my_capture_step} step cannot see {:seq}.
    # we can see {:captured} on the outside.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], :captured=>[{:model=>nil, :params=>nil}.inspect, {:model=>nil, :params=>nil}.inspect]}}

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success, target_ctx: {seq: [], pollute: true}
    # Since we don't allow :pollute, the my_capture_step doesn't see it.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], pollute: true, :captured=>[{:model=>nil, :params=>nil}.inspect, {:model=>nil, :params=>nil}.inspect]}}
  end

  it "without Out(), all variables are visible on the outside" do
    my_railway = Class.new(Trailblazer::Activity::Railway) do
      step my_capture_step,
        In() => [:model, :params, :pollute]
    end

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success
    # the {my_capture_step} step cannot see {:seq}.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], :captured=>[{:model=>nil, :params=>nil, :pollute=>nil}.inspect, {:model=>nil, :params=>nil}.inspect]}}

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success, target_ctx: {seq: [], pollute: true}
    # we can see pollute outside.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], pollute: 1, :captured=>[{:model=>nil, :params=>nil, :pollute=>true}.inspect, {:model=>nil, :params=>nil}.inspect]}}
  end

  it "with Out(), we only see {:captured}" do
    my_railway = Class.new(Trailblazer::Activity::Railway) do
      step my_capture_step,
        In() => [:model, :params, :pollute],
        Out() => [:captured]
    end

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success
    #
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], :captured=>[{:model=>nil, :params=>nil, :pollute=>nil}.inspect, {:model=>nil, :params=>nil}.inspect]}}

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success, target_ctx: {seq: [], pollute: true}
    # we cannot see pollute outside.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], pollute: true, :captured=>[{:model=>nil, :params=>nil, :pollute=>true}.inspect, {:model=>nil, :params=>nil}.inspect]}}
  end

  it "" do
    my_railway = Class.new(Trailblazer::Activity::Railway) do
      step my_capture_step,
        In() => [:model, :params],
        Inject() => [:pollute],
        Out() => [:captured]
    end

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success
    # {:pollute} is absent in target_ctx and thus not visible inside.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], :captured=>[{:model=>nil, :params=>nil}.inspect, {:model=>nil, :params=>nil}.inspect]}}

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success, target_ctx: {seq: [], pollute: true}
    # we cannot see pollute outside.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], pollute: true, :captured=>[{:pollute=>true, :model=>nil, :params=>nil}.inspect, {:model=>nil, :params=>nil}.inspect]}}
  end

  it "when inheriting, the {:exec_context} of respective nodes gets updated" do
    my_nested_topology = Class.new(Trailblazer::Activity::Railway) do
      step :d
      include T.def_steps(:d)
    end

    my_topology = Class.new(Trailblazer::Activity::Railway) do
      step T.def_steps(:a).method(:a)
      step :b
      step :c, Trailblazer::Activity::Railway.In() => :my_ins
      # step Subprocess(my_nested_topology), id: :D
      step task: my_nested_topology, id: :D, outputs: my_nested_topology.to_h[:outputs], subprocess: true, adapter: Trailblazer::Circuit::Processor

      def my_ins(ctx, seq:, **)
        {seq: seq + [:my_ins]}
      end

      include T.def_steps(:b, :c)
    end

    my_sub_topology = Class.new(my_topology) do
      def my_ins(ctx, seq:, **)
        {seq: seq + [:my_ins_from_sub]}
      end

      def b(ctx, seq:, **)
        seq << :b_from_sub
      end
    end

    lib_ctx, _ = assert_run my_topology, terminus: :success, seq: [:a, :b, :my_ins, :c, :d]
    assert_equal lib_ctx, {target_ctx: {seq: [:a, :b, :my_ins, :c, :d]}}

    lib_ctx, _ = assert_run my_sub_topology, terminus: :success, seq: [:a, :b_from_sub, :my_ins_from_sub, :c, :d]
  end
end
