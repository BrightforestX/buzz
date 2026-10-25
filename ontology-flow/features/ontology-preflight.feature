# Manifest: PRODUCT-B-agent-dispatch (S01 wire — ontology gate)
# Rust: crates/buzz-agent/tests/ontology_gate.rs
# Playwright stub: desktop/tests/e2e/ontology-preflight.spec.ts
Feature: Buzz agent ontology preflight at session start

  Background:
    Given buzz-agent is configured with BUZZ_AGENT_ONTOLOGY_GATE=1
    And an MCP server exposes validate_proposal

  Scenario: Session starts when validate_proposal returns ok
    When the client calls session/new with the px-validate MCP server
    Then buzz-agent calls validate_proposal with class_name PlatformJob
    And the session is created with a sessionId

  Scenario: Session is rejected when validate_proposal fails
    When validate_proposal returns ok false with errors
    And the client calls session/new
    Then session/new returns an ontology gate error
    And no sessionId is returned

  Scenario: Session is rejected when validate_proposal tool is missing
    When the client calls session/new without any MCP servers
    Then session/new fails closed with a missing validate_proposal error

  Scenario: Ontology gate is skipped when disabled
    Given BUZZ_AGENT_ONTOLOGY_GATE is unset or 0
    When the client calls session/new without MCP servers
    Then the session is created normally
