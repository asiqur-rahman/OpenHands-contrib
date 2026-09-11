// @vitest-environment node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);

const resolverPath = path.join(
  repoRoot,
  "tests/e2e/mock-llm/scripts/resolve-affected-tests.mjs",
);
const workflowPath = path.join(repoRoot, ".github/workflows/mock-llm-e2e.yml");
const dockerWorkflowPath = path.join(
  repoRoot,
  ".github/workflows/mock-llm-docker-e2e.yml",
);
const ciWorkflowPath = path.join(repoRoot, ".github/workflows/ci.yml");

function resolveAffectedTests(files: string[]) {
  const output = execFileSync(
    process.execPath,
    [resolverPath, "--files", files.join(",")],
    { cwd: repoRoot, encoding: "utf-8" },
  ).trim();

  return output.length > 0 ? output.split(/\s+/) : [];
}

describe("mock-LLM E2E affected test resolver", () => {
  it("selects mapped source shards plus regressions", () => {
    expect(
      resolveAffectedTests(["src/components/features/settings/llm-form.tsx"]),
    ).toEqual([
      "tests/e2e/mock-llm/regressions",
      "tests/e2e/mock-llm/settings",
    ]);
  });

  it("runs the full suite for cross-cutting source changes", () => {
    expect(resolveAffectedTests(["src/api/agent-server-adapter.ts"])).toEqual([
      "__ALL__",
    ]);
  });

  it("runs the full suite for unmapped source changes", () => {
    expect(resolveAffectedTests(["src/utils/some-new-helper.ts"])).toEqual([
      "__ALL__",
    ]);
  });

  it("selects the containing feature subset for a test-only new spec change", () => {
    expect(
      resolveAffectedTests([
        "tests/e2e/mock-llm/mcp/mock-llm-new-marketplace.spec.ts",
      ]),
    ).toEqual(["tests/e2e/mock-llm/mcp", "tests/e2e/mock-llm/regressions"]);
  });

  it("selects the exact root spec path defensively for misplaced new specs", () => {
    expect(
      resolveAffectedTests(["tests/e2e/mock-llm/mock-llm-new-root.spec.ts"]),
    ).toEqual([
      "tests/e2e/mock-llm/regressions",
      "tests/e2e/mock-llm/mock-llm-new-root.spec.ts",
    ]);
  });

  it.each([
    ["public/favicon.ico"],
    [".github/workflows/mock-llm-e2e.yml"],
    ["tailwind.config.js"],
    ["hero.ts"],
    ["tests/e2e/mock-llm/test-mapping.json"],
  ])("runs the full suite for relevant trigger path %s", (file) => {
    expect(resolveAffectedTests([file])).toEqual(["__ALL__"]);
  });

  // This fork triggers mock-llm-e2e.yml on every PR commit (branches:
  // [production]) plus manual dispatch, gated by a detect-pr-changes job --
  // not on a push-to-main trigger like upstream, since workflow_run doesn't
  // fire for a new workflow file until it's already on the default branch.
  it("runs browser mock E2E on production PRs or manual dispatch", () => {
    const workflow = readFileSync(workflowPath, "utf-8");

    expect(workflow).toContain("pull_request:");
    expect(workflow).toContain("branches: [production]");
    expect(workflow).toContain("workflow_dispatch:");
    expect(workflow).toContain("detect-pr-changes:");
    expect(workflow).toContain('PW_CMD="npm run test:e2e:mock-llm"');
  });

  // Same fork-specific reasoning as above, plus workflow_run to validate the
  // image once it's actually published from production.
  it("runs Docker mock E2E after successful production builds, on PRs, or manual dispatch", () => {
    const dockerWorkflow = readFileSync(dockerWorkflowPath, "utf-8");

    expect(dockerWorkflow).toContain('workflows: ["Docker"]');
    expect(dockerWorkflow).toContain("branches: [production]");
    expect(dockerWorkflow).toContain("workflow_dispatch:");
    expect(dockerWorkflow).toContain("pull_request:");
    expect(dockerWorkflow).toContain("detect-pr-changes:");
    expect(dockerWorkflow).toContain(
      "github.event.workflow_run.conclusion == 'success'",
    );
  });

  it("runs live LLM E2E on production or by manual PR dispatch", () => {
    const ciWorkflow = readFileSync(ciWorkflowPath, "utf-8");
    const liveJob = ciWorkflow.slice(ciWorkflow.indexOf("  live-e2e:"));

    expect(liveJob).toContain("github.event_name == 'workflow_dispatch'");
    expect(liveJob).toContain(
      "github.event_name == 'push' && github.ref == 'refs/heads/production'",
    );
    expect(liveJob).not.toContain("github.event_name == 'pull_request'");
    expect(liveJob).toContain(
      "LIVE_E2E_PR_NUMBER: ${{ inputs.pr_number || '' }}",
    );
  });
});
