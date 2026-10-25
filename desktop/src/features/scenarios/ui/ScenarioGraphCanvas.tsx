import * as React from "react";
import {
  forceCenter,
  forceLink,
  forceManyBody,
  forceSimulation,
  type SimulationLinkDatum,
  type SimulationNodeDatum,
} from "d3-force";
import { select } from "d3-selection";

import type {
  MirofishGraphEdge,
  MirofishGraphNode,
} from "@/features/scenarios/mirofishGraphTypes";
import { cn } from "@/shared/lib/cn";

type SimNode = MirofishGraphNode &
  SimulationNodeDatum & { entityType: string; color: string };

type SimLink = SimulationLinkDatum<SimNode> & { label?: string };

const PALETTE = [
  "#FF6B35",
  "#004E89",
  "#7B2D8E",
  "#1A936F",
  "#C5283D",
  "#3498db",
  "#9b59b6",
  "#27ae60",
];

function entityType(node: MirofishGraphNode): string {
  return node.labels?.find((label) => label !== "Entity") ?? "Entity";
}

type ScenarioGraphCanvasProps = {
  nodes: MirofishGraphNode[];
  edges: MirofishGraphEdge[];
  className?: string;
};

export function ScenarioGraphCanvas({
  nodes,
  edges,
  className,
}: ScenarioGraphCanvasProps) {
  const containerRef = React.useRef<HTMLDivElement>(null);
  const svgRef = React.useRef<SVGSVGElement>(null);
  const [selected, setSelected] = React.useState<MirofishGraphNode | null>(
    null,
  );

  React.useEffect(() => {
    const container = containerRef.current;
    const svgEl = svgRef.current;
    if (!container || !svgEl || nodes.length === 0) {
      return;
    }

    const width = container.clientWidth;
    const height = container.clientHeight;
    const typeColors = new Map<string, string>();
    const simNodes: SimNode[] = nodes.map((node) => {
      const type = entityType(node);
      if (!typeColors.has(type)) {
        typeColors.set(
          type,
          PALETTE[typeColors.size % PALETTE.length] ?? "#888",
        );
      }
      return {
        ...node,
        entityType: type,
        color: typeColors.get(type) ?? "#888",
      };
    });
    const nodeById = new Map(simNodes.map((node) => [node.uuid, node]));
    const simLinks: SimLink[] = edges
      .map((edge) => {
        const source = nodeById.get(edge.source_uuid ?? "");
        const target = nodeById.get(edge.target_uuid ?? "");
        if (!source || !target) {
          return null;
        }
        return {
          source,
          target,
          label: edge.name ?? edge.fact,
        };
      })
      .filter(Boolean) as SimLink[];

    const svg = select(svgEl)
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", `0 0 ${width} ${height}`);
    svg.selectAll("*").remove();

    const link = svg
      .append("g")
      .attr("stroke", "#94a3b8")
      .attr("stroke-opacity", 0.6)
      .selectAll("line")
      .data(simLinks)
      .join("line")
      .attr("stroke-width", 1.5);

    const node = svg
      .append("g")
      .selectAll("circle")
      .data(simNodes)
      .join("circle")
      .attr("r", 10)
      .attr("fill", (d) => d.color)
      .attr("stroke", "#fff")
      .attr("stroke-width", 1.5)
      .style("cursor", "pointer")
      .on("click", (_event, d) => setSelected(d));

    const labels = svg
      .append("g")
      .selectAll("text")
      .data(simNodes)
      .join("text")
      .text((d) => d.name ?? d.uuid.slice(0, 8))
      .attr("font-size", 10)
      .attr("fill", "currentColor")
      .attr("pointer-events", "none");

    const simulation = forceSimulation(simNodes)
      .force(
        "link",
        forceLink(simLinks)
          .id((d) => (d as SimNode).uuid)
          .distance(80),
      )
      .force("charge", forceManyBody().strength(-120))
      .force("center", forceCenter(width / 2, height / 2))
      .on("tick", () => {
        link
          .attr("x1", (d) => (d.source as SimNode).x ?? 0)
          .attr("y1", (d) => (d.source as SimNode).y ?? 0)
          .attr("x2", (d) => (d.target as SimNode).x ?? 0)
          .attr("y2", (d) => (d.target as SimNode).y ?? 0);
        node.attr("cx", (d) => d.x ?? 0).attr("cy", (d) => d.y ?? 0);
        labels
          .attr("x", (d) => (d.x ?? 0) + 12)
          .attr("y", (d) => (d.y ?? 0) + 4);
      });

    return () => {
      simulation.stop();
    };
  }, [edges, nodes]);

  if (nodes.length === 0) {
    return (
      <div
        className={cn(
          "flex min-h-[320px] items-center justify-center rounded-xl border border-dashed border-border/70 text-sm text-muted-foreground",
          className,
        )}
      >
        No graph nodes — check MiroFish backend and zep-shim, or pick another
        graph id.
      </div>
    );
  }

  return (
    <div
      className={cn(
        "relative min-h-[420px] rounded-xl border border-border/70",
        className,
      )}
    >
      <div className="absolute left-3 top-3 z-10 rounded-md bg-background/90 px-2 py-1 text-xs text-muted-foreground backdrop-blur">
        {nodes.length} nodes · {edges.length} edges
      </div>
      <div ref={containerRef} className="absolute inset-0">
        <svg ref={svgRef} className="h-full w-full text-foreground" />
      </div>
      {selected ? (
        <div className="absolute bottom-3 right-3 z-10 max-w-sm rounded-lg border border-border bg-card/95 p-3 text-sm shadow-lg backdrop-blur">
          <div className="font-medium">{selected.name ?? "Node"}</div>
          <div className="text-xs text-muted-foreground">
            {entityType(selected)}
          </div>
          {selected.summary ? (
            <p className="mt-2 line-clamp-4 text-xs">{selected.summary}</p>
          ) : null}
          <button
            className="mt-2 text-xs text-primary hover:underline"
            onClick={() => setSelected(null)}
            type="button"
          >
            Close
          </button>
        </div>
      ) : null}
    </div>
  );
}
