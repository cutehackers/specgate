# Screen Abstraction: [FEATURE NAME]

**Feature Directory**: `/path/to/feature`  
**Spec**: `<feature_dir>/docs/spec.md`  
**Related Plan**: `<feature_dir>/docs/code.md`  
**Created**: [DATE]

## Purpose

Define screen-level contracts only. This document is the source of truth for
screen behavior contracts used by downstream `code.md` and `quickstart.md`.

## Global Guardrails

- Keep this document implementation-agnostic
- Do not include widget tree details
- Do not include layout measurements, pixel values, or style tokens
- Do not include animation or motion timing values
- Do not include framework-specific component names

## Story Coverage Map

- [US1]: [screen ids]
- [US2]: [screen ids]
- [US3]: [screen ids]

## Screen Contracts

### Screen: [SCREEN_ID]

- `screen`: [stable identifier]
- `story`: [US1, US2 ...]
- `purpose`: [user intent and success condition]
- `input`: [required data + inbound context]
- `output`: [domain outcomes + outbound navigation effect]
- `ui_state`:
  - loading: [definition]
  - empty: [definition]
  - success: [definition]
  - error: [definition]
  - disabled/offline: [definition if needed]
- `event`:
  - [event_name]: [mapped domain action/use case]
  - [event_name]: [mapped domain action/use case]
- `error_state`:
  - [error_case]: [user-visible response + recovery action]
  - [error_case]: [user-visible response + recovery action]
- `dependencies`:
  - [provider/use case/repository]
  - [provider/use case/repository]

### Screen: [SCREEN_ID]

- `screen`: [stable identifier]
- `story`: [US1, US2 ...]
- `purpose`: [user intent and success condition]
- `input`: [required data + inbound context]
- `output`: [domain outcomes + outbound navigation effect]
- `ui_state`:
  - loading: [definition]
  - empty: [definition]
  - success: [definition]
  - error: [definition]
  - disabled/offline: [definition if needed]
- `event`:
  - [event_name]: [mapped domain action/use case]
- `error_state`:
  - [error_case]: [user-visible response + recovery action]
- `dependencies`:
  - [provider/use case/repository]

## Validation Checklist

- [ ] Every P1/P2 user story is mapped to at least one screen
- [ ] Every screen has all required schema fields
- [ ] Every `event` maps to a domain action/use case
- [ ] No concrete visual implementation details are included
