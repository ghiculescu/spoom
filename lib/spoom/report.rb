# typed: false
# frozen_string_literal: true

require_relative "file_tree"
require_relative "git"
require_relative "metrics"

require "date"

module Spoom
  module Coverage
    def self.sigils_tree
      config = Spoom::Sorbet::Config.parse_file(Spoom::Config::SORBET_CONFIG)
      files = Spoom::Sorbet.srb_files(config)
      files.select! { |file| file =~ /\.rb$/ }
      FileTree.from_paths(files)
    end

    def self.report
      Spoom::Coverage::Report.new(
        snapshots: [Spoom::Metrics.snapshot],
        sigils_tree: self.sigils_tree,
      )
    end

    # Utils

      # TODO sorbet intro
      # TODO timeline

    # def self.sorbet_intro_time
      # Spoom::Git.exec("git log --diff-filter=A --format='%h %at'  -- sorbet/config")
    # end

    class Report < T::Struct
      extend T::Sig

      const :sigils_tree, FileTree
      const :snapshots, T::Array[Spoom::Metrics::Snapshot]

      def title
        return "Typing Coverage" if snapshots.empty?
        snapshots.last.project
      end

      sig { returns(String) }
      def html_header
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta http-equiv="x-ua-compatible" content="ie=edge" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />

            <title>#{title}</title>
            <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.0/css/bootstrap.min.css">

            <style>
            #{html_style}
            </style>
          </head>
          <body>
            <script src="https://code.jquery.com/jquery-3.5.1.slim.min.js"></script>
            <script src="https://stackpath.bootstrapcdn.com/bootstrap/4.5.0/js/bootstrap.min.js"></script>
            <script src="https://d3js.org/d3.v4.min.js"></script>

            <script>#{html_script}</script>

            <div class="px-5 py-4">
        HTML
      end

      sig { returns(String) }
      def html_body
        <<~HTML
          <h1 class="display-3">
            #{title}
            <span class="badge badge-pill badge-dark" style="font-size: 20%;">#{snapshots.last.commit_sha}</span>
          </h1>
          <br>

          <div class="card">
            <div class="card-body">
              <h5 class="card-title">Sigils</h5>
              <div class="row row-cols-1 row-cols-md-2">
                <div class="col mb-6">
                  <div id="pie_sigils"></div>
                  <script>#{pie_chart("sigils", last_sigils)}</script>
                </div>
                <div class="col mb-6">
                  <div id="sigils_timeline"></div>
                </div>
              </div>
            </div>
          </div>
          <br>

          <div class="card">
            <div class="card-body">
              <h5 class="card-title">Calls</h5>
              <div class="row row-cols-1 row-cols-md-2">
                <div class="col mb-6">
                  <div id="pie_calls"></div>
                  <script>#{pie_chart("calls", last_calls)}</script>
                </div>
                <div class="col mb-6">
                  <div id="sigils_timeline"></div>
                </div>
              </div>
            </div>
          </div>
          <br>

          <div class="card">
            <div class="card-body">
              <h5 class="card-title">Signatures</h5>
              <div class="row row-cols-1 row-cols-md-2">
                <div class="col mb-6">
                  <div id="pie_sigs"></div>
                  <script>#{pie_chart("sigs", last_sigs)}</script>
                </div>
                <div class="col mb-6">
                  <div id="sigils_timeline"></div>
                </div>
              </div>
            </div>
          </div>
          <br>

          <div class="card">
            <div class="card-body">
              <h5 class="card-title">Strictness Map</h5>
              <div id="map_sigils"></div>
              <script>#{circle_map("sigils", sigils_tree.root)}</script>
            </div>
          </div>
          <br>

          <div class="card">
            <div class="card-body">
              <h5 class="card-title">Raw Data</h5>
              <a data-toggle="collapse" href="#collapseRawData">Toogle</a>
              <div class="collapse" id="collapseRawData">
                <pre><code>#{JSON.pretty_generate(snapshots.last.metrics.serialize)}</code></pre>
              </div>
            </div>
          </div>

          Sorbet version <a href="https://rubygems.org/gems/sorbet/versions/#{snapshots.last.sorbet_version}">
                  #{snapshots.last.sorbet_version}</a>

        HTML
      end

      def html_style
        <<~STYLE
          .tooltip {
              position: absolute;
              top: 0;
              left: 0;
              text-align: center;
              padding: 5px;
              font: 12px sans-serif;
              background: rgba(0, 0, 0, 0.1);
              border: 0px;
              border-radius: 4px;
              pointer-events: none;
              opacity: 0;
          }

.node {
  cursor: pointer;
}

.node:hover {
  stroke: #333;
  stroke-width: 1px;
}

.node--leaf {
  fill: white;
}

.label--dir {
  font: 14px Arial, sans-serif;
  text-anchor: middle;
}

.label--leaf {
  font: 12px Arial, sans-serif;
  text-anchor: middle;
}

.label--dir,
.label--leaf,
.node--root,
.node--leaf {
  pointer-events: none;
}

.tooltip {
    position: absolute;
    text-align: center;
    padding: 5px;
    font: 12px sans-serif;
    background: rgba(0, 0, 0, 0.2);
    border: 0px;
    border-radius: 4px;
    pointer-events: none;
}
        STYLE
      end

      def html_script
        <<~SCRIPT
        function strictnessColor(strictness) {
          switch(strictness) {
            case "false":
              return "#db4437";
            case "true":
              return "#0f9d58";
            case "strict":
              return "#0a7340";
            case "strong":
              return "#064828";
          }
          return "#ccc";
        }

        var dirColor = d3.scaleLinear()
          .domain([1, 0])
          .range(["#0f9d58", "#db4437"])//, "#0f9d58", "#0a7340", "#064828"])
          .interpolate(d3.interpolateRgb);

        function toPercent(value, sum) {
          return Math.round(value * 100 / sum) + "%";
        }

        function treeHeight(root, height = 0) {
          height += 1;

          if (root.children && root.children.length > 0)
            return Math.max(...root.children.map(child => treeHeight(child, height)));
          else
            return height;
        }

        function zoom(d) {
          var focus0 = focus; focus = d;

          var transition = d3.transition()
              .duration(d3.event.altKey ? 7500 : 750)
              .tween("zoom", function(d) {
                var i = d3.interpolateZoom(view, [focus.x, focus.y, focus.r * 2]);
                return function(t) { zoomTo(i(t)); };
              });

          transition.selectAll("text")
            .filter(function(d) { return d.parent === focus || this.style.display === "inline"; })
              .style("fill-opacity", function(d) { return d.parent === focus ? 1 : 0; })
              .on("start", function(d) { if (d.parent === focus) this.style.display = "inline"; })
              .on("end", function(d) { if (d.parent !== focus) this.style.display = "none"; });
        }

        var tooltip = d3.select("body")
          .append("div")
            .append("div")
              .attr("class", "tooltip");

        var tooltipSigils = function(d) {
          tooltip
            .style("left", (d3.event.pageX + 20) + "px")
            .style("top", (d3.event.pageY) + "px")
            .html("<b>typed: " + d.data.key + "<br>" + toPercent(d.data.value, sum_sigils) +
              " - " + d.data.value + " files</b>")
        }

        var pie_size = 200;
        var pie_radius = pie_size / 2;

        var arcGenerator = d3.arc()
          .innerRadius(50)
          .outerRadius(pie_radius);

        var tooltip_calls = function(d) {
          tooltip
            .style("left", (d3.event.pageX + 20) + "px")
            .style("top", (d3.event.pageY) + "px")
            .html("<b>" + toPercent(d.data.value, sum_calls) +
              (d.data.key == "true" ? " checked" : " unchecked") +
              "</b><br>" + d.data.value + " calls");
        }

        var tooltip_sigils = function(d) {
          tooltip
            .style("left", (d3.event.pageX + 20) + "px")
            .style("top", (d3.event.pageY) + "px")
            .html("<b>typed: " + d.data.key + "<br>" + toPercent(d.data.value, sum_sigils) +
              " - " + d.data.value + " files</b>")
        }

        var tooltip_sigs = function(d) {
          tooltip
            .style("left", (d3.event.pageX + 20) + "px")
            .style("top", (d3.event.pageY) + "px")
            .html("<b>" + toPercent(d.data.value, sum_sigs) +
              (d.data.key == "true" ? " with" : " without") +
              " a signature</b><br>" + d.data.value + " methods");
        }

        SCRIPT
      end

      def pie_chart(id, data)
        <<~JS
          var pie_#{id} = d3.pie().value(function(d) { return d.value; });
          var json_#{id} = #{data.to_json};
          var data_#{id} = pie_#{id}(d3.entries(json_#{id}));
          var sum_#{id} = d3.sum(data_#{id}, function(d) { return d.data.value; });

          var svg_#{id} = d3.select("#pie_#{id}")
            .append("svg")
              .attr("width", pie_size)
              .attr("height", pie_size)
              .append("g")
                .attr("transform", "translate(" + pie_size / 2 + "," + pie_size / 2 + ")");

          svg_#{id}.selectAll("arcs")
            .data(data_#{id})
            .enter()
              .append('path')
                .attr('fill', function(d) { return strictnessColor(d.data.key); })
                .attr('d', arcGenerator)
                .on("mouseover", function(d) { tooltip.style("opacity", 1); })
                .on("mousemove", tooltip_#{id})
                .on("mouseleave", function(d) { tooltip.style("opacity", 0); });

          svg_#{id}.selectAll("labels")
            .data(data_#{id})
            .enter()
              .append('text')
              .text(function(d) { return toPercent(d.data.value, sum_#{id}); })
              .attr("transform", function(d) { return "translate(" + arcGenerator.centroid(d) + ")"; })
              .style("text-anchor", "middle")
              .style("font-size", "14px")
              .style("fill", "#fff")
        JS
      end

      def circle_map(id, data)
        <<~JS
        var root = #{data.to_json};
        var diameter = document.getElementById("map_#{id}").clientWidth;

        var svg_#{id} = d3.select("#map_#{id}")
          .append("svg")
            .attr("width", diameter)
            .attr("height", diameter)
            .append("g")
              .attr("transform", "translate(" + diameter / 2 + "," + diameter / 2 + ")");

        var dataHeight = treeHeight(root)

        var opacity = d3.scaleLinear()
            .domain([0, dataHeight])
            .range([0, 0.3])

        var pack = d3.pack()
            .size([diameter, diameter])
            .padding(2);

        root = d3.hierarchy(root)
            .sum(function(d) { return d.children ? d.children.length : 1; })
            .sort(function(a, b) { return b.value - a.value; });

        var focus = root,
            nodes = pack(root).descendants(),
            view;

        var mousemove = function(d) {
          tooltip
            .html("<b>" + d.data.name + "</b>")
            .style("left", (d3.event.pageX+20) + "px")
            .style("top", (d3.event.pageY) + "px")
        }

        function redraw(){

          var circle = svg_#{id}.selectAll("circle")
            .data(nodes)
            .enter().append("circle")
              .attr("class", function(d) { return d.parent ? d.children ? "node" : "node node--leaf" : "node node--root"; })
              .style("fill", function(d) { return d.children ? dirColor(d.data.score) : strictnessColor(d.data.strictness); })
              .style("fill-opacity", function(d) { return d.children ? opacity(d.depth) : 1; })
              .on("click", function(d) { if (focus !== d) zoom(d), d3.event.stopPropagation(); })
              .on("mouseover", function(d) { tooltip.style("opacity", 1); })
              .on("mousemove", mousemove)
              .on("mouseleave", function(d) { tooltip.style("opacity", 0); });

          var text = svg_#{id}.selectAll("text")
            .data(nodes)
            .enter().append("text")
              .attr("class", function(d) { return d.children ? "label--dir" : "label--leaf"; })
              .style("fill-opacity", function(d) { return d.depth <= 1 ? 1 : 0; })
              .style("display", function(d) { return d.depth <= 1 ? "inline" : "none"; })
              .text(function(d) { return d.data.name; });

          var node = svg_#{id}.selectAll("circle,text");

        function zoomTo(v) {
          var k = diameter / v[2]; view = v;
          node.attr("transform", function(d) { return "translate(" + (d.x - v[0]) * k + "," + (d.y - v[1]) * k + ")"; });
          circle.attr("r", function(d) { return d.r * k; });
        }
        zoomTo([root.x, root.y, root.r * 2]);

        }

        svg_#{id}.on("click", function() { zoom(root); });

      // Draw for the first time to initialize.
      redraw();

      // Redraw based on the new size whenever the browser window is resized.
      window.addEventListener("resize", redraw);
        JS
      end

      sig { returns(String) }
      def html_footer
        <<~HTML
              <br>
              <div class="text-center">
                Generated by <a href="https://github.com/Shopify/spoom">spoom</a>
                on #{Time.now.utc}
              </div>
            </div>
          </body>
          </html>
        HTML
      end

      sig { returns(String) }
      def html
        html = StringIO.new
        html << html_header
        html << html_body
        html << html_footer
        html.string
      end

      private

      def last_calls
        {
          true: snapshots.last.metrics["types.input.sends.typed"],
          false: snapshots.last.metrics["types.input.sends.total"] - snapshots.last.metrics["types.input.sends.typed"]
        }
      end

      def last_sigils
        snapshots.last.metrics.files_by_strictness.select{ |k, v| v }
      end

      def last_sigs
        {
          true: snapshots.last.metrics["types.sig.count"],
          false: snapshots.last.metrics["types.input.methods.total"] - snapshots.last.metrics["types.sig.count"]
        }
      end

      def format_timestamp(timestamp)
        DateTime.strptime(timestamp.to_s, '%s').strftime('%F %I:%M %p')
      end
    end

      # def to_json(*args)
        # obj = { name: name }
#
        # if strictness
          # obj[:strictness] = strictness
        # end
#
        # if children.size > 0
          # obj[:children] = children.values
          # obj[:score] = score
        # end
#
        # obj.to_json(*args)
      # end
#
      # def score
        # unless @score
          # @score = 0
          # if name =~ /\.rbi?$/
            # case strictness
            # when "true", "strict", "strong"
              # @score = 1.0
            # end
          # elsif !children.empty?
              # @score = children.values.sum(&:score) / children.size.to_f
          # end
        # end
        # @score
      # end

      def strictness
        return nil unless name =~ /\.rbi?$/
        unless @strictness
          @strictness = Spoom::Sorbet::Sigils.file_strictness(path)
        end
        @strictness

  end
end
