# typed: true
# frozen_string_literal: true

require "spoom/sorbet/sigils"
require "spoom/sorbet/config"
require "spoom/sorbet/errors"
require "spoom/sorbet/lsp"

require "open3"

module Spoom
  module Sorbet
    extend T::Sig

    sig { params(arg: String, path: String, capture_err: T::Boolean).returns([String, T::Boolean]) }
    def self.srb(*arg, path: '.', capture_err: false)
      opts = {}
      opts[:chdir] = path
      out = T.let("", T.nilable(String))
      res = T.let(false, T::Boolean)
      if capture_err
        Open3.popen2e(["bundle", "exec", "srb", *arg].join(" "), opts) do |_, o, t|
          out = o.read
          res = T.cast(t.value, Process::Status).success?
        end
      else
        Open3.popen2(["bundle", "exec", "srb", *arg].join(" "), opts) do |_, o, t|
          out = o.read
          res = T.cast(t.value, Process::Status).success?
        end
      end
      [out || "", res]
    end

    sig { params(arg: String, path: String, capture_err: T::Boolean).returns([String, T::Boolean]) }
    def self.srb_tc(*arg, path: '.', capture_err: false)
      srb(*T.unsafe(["tc", *arg]), path: path, capture_err: capture_err)
    end

    # List all files typechecked by Sorbet from its `config`
    sig { params(config: Config, path: String).returns(T::Array[String]) }
    def self.srb_files(config, path: '.')
      regs = config.ignore.map { |string| Regexp.new(Regexp.escape(string)) }
      exts = config.allowed_extensions.empty? ? ['.rb', '.rbi'] : config.allowed_extensions
      Dir.glob((Pathname.new(path) / "**/*{#{exts.join(',')}}").to_s).reject do |f|
        regs.any? { |re| re.match?(f) }
      end.sort
    end
  end
end
