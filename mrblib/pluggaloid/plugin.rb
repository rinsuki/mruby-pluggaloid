# -*- coding: utf-8 -*-

# プラグインの本体。
# DSLを提供し、イベントやフィルタの管理をする
module Pluggaloid
  class Plugin
    include InstanceStorage

    class << self
      attr_writer :vm

      def vm
        @vm ||= begin
                  raise Pluggaloid::NoDefaultDelayerError, "Default Delayer was not set." unless Delayer.default
                  vm = Pluggaloid::VM.new(
                    Delayer.default,
                    self,
                    Pluggaloid::Event,
                    Pluggaloid::Listener,
                    Pluggaloid::Filter)
                  vm.Event.vm = vm end end

      # プラグインのインスタンスを返す。
      # ブロックが渡された場合、そのブロックをプラグインのインスタンスのスコープで実行する
      # ==== Args
      # [plugin_name] プラグイン名
      # ==== Return
      # Plugin
      def create(plugin_name, &body)
        self[plugin_name].instance_eval(&body) if body
        self[plugin_name] end

      # イベントを宣言する。
      # ==== Args
      # [event_name] イベント名
      # [options] 以下のキーを持つHash
      # :prototype :: 引数の数と型。Arrayで、type_strictが解釈できる条件を設定する
      # :priority :: Delayerの優先順位
      def defevent(event_name, options = {})
        vm.Event[event_name].options = options end

      # イベント _event_name_ を発生させる
      # ==== Args
      # [event_name] イベント名
      # [*args] イベントの引数
      # ==== Return
      # Delayer
      def call(event_name, *args)
        vm.Event[event_name].call(*args) end

      # 引数 _args_ をフィルタリングした結果を返す
      # ==== Args
      # [*args] 引数
      # ==== Return
      # フィルタされた引数の配列
      def filtering(event_name, *args)
        vm.Event[event_name].filtering(*args) end

      # 互換性のため
      def uninstall(plugin_name)
        self[plugin_name].uninstall end

      # 互換性のため
      def filter_cancel!
        vm.Filter.cancel! end

      alias plugin_list instances_name

      alias __clear_aF4e__ clear!
      def clear!
        if defined?(@vm) and @vm
          @vm.Event.clear!
          @vm = nil end
        __clear_aF4e__() end
    end

    # プラグインの名前
    attr_reader :name

    # spec
    attr_accessor :spec

    # 最初にプラグインがロードされた時刻(uninstallされるとリセットする)
    attr_reader :defined_time

    # ==== Args
    # [plugin_name] プラグイン名
    def initialize(*args)
      super
      @defined_time = Time.new
      @events = Set.new
      @filters = Set.new end

    # イベントリスナを新しく登録する
    # ==== Args
    # [event_name] イベント名
    # [&callback] イベントのコールバック
    # ==== Return
    # Pluggaloid::Listener
    def add_event(event_name, &callback)
      result = vm.Listener.new(vm.Event[event_name], &callback)
      @events << result
      result end

    # イベントフィルタを新しく登録する
    # ==== Args
    # [event_name] イベント名
    # [&callback] イベントのコールバック
    # ==== Return
    # EventFilter
    def add_event_filter(event_name, &callback)
      result = vm.Filter.new(vm.Event[event_name], &callback)
      @filters << result
      result end

    # イベントを削除する。
    # 引数は、Pluggaloid::ListenerかPluggaloid::Filterのみ(on_*やfilter_*の戻り値)。
    # 互換性のため、二つ引数がある場合は第一引数は無視され、第二引数が使われる。
    # ==== Args
    # [*args] 引数
    # ==== Return
    # self
    def detach(*args)
      listener = args.last
      if listener.is_a? vm.Listener
        @events.delete(listener)
        listener.detach
      elsif listener.is_a? vm.Filter
        @filters.delete(listener)
        listener.detach end
      self end

    # このプラグインを破棄する
    # ==== Return
    # self
    def uninstall
      @events.map(&:detach)
      @filters.map(&:detach)
      self.class.destroy name
      execute_unload_hook
      self end

    # イベント _event_name_ を宣言する
    # ==== Args
    # [event_name] イベント名
    # [options] イベントの定義
    def defevent(event_name, options={})
      vm.Event[event_name].options.merge!({plugin: self}.merge(options)) end

    # DSLメソッドを新しく追加する。
    # 追加されたメソッドは呼ぶと &callback が呼ばれ、その戻り値が返される。引数も順番通り全て &callbackに渡される
    # ==== Args
    # [dsl_name] 新しく追加するメソッド名
    # [&callback] 実行されるメソッド
    # ==== Return
    # self
    def defdsl(dsl_name, &callback)
      self.class.instance_eval {
        define_method(dsl_name, &callback) }
      self end

    # プラグインが Plugin.uninstall される時に呼ばれるブロックを登録する。
    def onunload
      @unload_hook ||= []
      @unload_hook.push(Proc.new) end
    alias :on_unload :onunload

    # マジックメソッドを追加する。
    # on_?name :: add_event(name)
    # filter_?name :: add_event_filter(name)
    def method_missing(method, *args, &proc)
      method_name = method.to_s
      def method_name.match_prefix(prefix)
        if self.start_with?(prefix + '_') && self.length > prefix.length + 1
          self[prefix.length + 1, self.length - 1]
        elsif self.start_with?(prefix) && self.length > prefix.length
          self[prefix.length, self.length - 1] end end
      
      if name = method_name.match_prefix('on')
        add_event(name.to_sym, &proc)
      elsif name = method_name.match_prefix('filter')
        add_event_filter(name.to_sym, &proc)
      elsif name = method_name.match_prefix('hook')
        add_event_hook(name.to_sym, &proc)
      else
        super end end

    private

    def execute_unload_hook
      @unload_hook.each{ |unload| unload.call } if(defined?(@unload_hook)) end

    def vm
      self.class.vm end

  end
end
