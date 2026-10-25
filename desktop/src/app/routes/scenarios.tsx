import * as React from "react";
import { createFileRoute } from "@tanstack/react-router";

import { usePreviewFeatureWarning } from "@/shared/features";
import { ViewLoadingFallback } from "@/shared/ui/ViewLoadingFallback";

const ScenariosScreen = React.lazy(async () => {
  const module = await import("@/features/scenarios/ui/ScenariosScreen");
  return { default: module.ScenariosScreen };
});

type ScenariosRouteSearch = {
  graphId?: string;
};

function validateScenariosSearch(
  search: Record<string, unknown>,
): ScenariosRouteSearch {
  const graphId =
    typeof search.graphId === "string" && search.graphId.length > 0
      ? search.graphId
      : undefined;
  return { graphId };
}

export const Route = createFileRoute("/scenarios")({
  validateSearch: validateScenariosSearch,
  component: ScenariosRouteComponent,
});

function ScenariosRouteComponent() {
  usePreviewFeatureWarning("scenarios");
  return (
    <React.Suspense fallback={<ViewLoadingFallback kind="scenarios" />}>
      <ScenariosScreen />
    </React.Suspense>
  );
}
