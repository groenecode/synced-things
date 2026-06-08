# Vault CRUD — Design

**Date:** 2026-06-08
**Branch:** `feature/vault-crud`
**Status:** Approved (pending spec review)

## Goal

Replace the current inline add/delete of vaults in `AppFeature` with proper CRUD:
a shared create/edit form, trailing swipe actions for edit and delete, and an
alert confirmation before deletion. Build it concretely for Vaults — no generic
or shared abstraction.

## Decisions

- **Form presentation:** a modal **sheet** for both create and edit. Same view
  and save logic; the only difference is how state is seeded.
- **Row tap:** tapping a row (outside the swipe) does nothing — reserved for a
  future Things drill-down.
- **Validation:** Save is disabled until the name, trimmed of whitespace, is
  non-empty. The `"Untitled Vault"` list fallback stays as a safety net for
  synced/legacy rows.

## Components

### 1. `VaultFormFeature` (new) — shared create/edit form

A pure form reducer plus a `Form`-based sheet view. It owns its own save.

- **State:** a `Vault.Draft` (SQLiteData's generated draft type), plus a
  `@Presents var alert` for save errors.
  - Create: seeded with an empty `Vault.Draft()` (no `id`).
  - Edit: seeded from an existing vault — `Vault.Draft(vault)` (carries `id`).
  - The two initializers are the only difference between create and edit.
- **Dependencies:** `\.defaultDatabase`, `\.date.now`, `\.dismiss`.
- **Save logic** (`saveButtonTapped`):
  - If the draft has no `id` → stamp `createdAt = now`, then `insert`.
  - If the draft has an `id` → `update`.
  - On success → `await dismiss()`.
  - On failure → surface an error alert; the sheet stays open.
- **Validation:** computed `isSaveDisabled` — `true` when the trimmed name is
  empty. The Save toolbar button binds to it.

### 2. `AppFeature` (modified) — list, owning present/edit/delete

- Removes the inline `addVaultButtonTapped` (which inserted a "New Vault") and
  the `.onDelete` handler.
- Introduces `@Reducer enum Destination`:
  - `case form(VaultFormFeature)` — presented as a sheet.
  - `case alert(AlertState<Alert>)` where
    `@CasePathable enum Alert { case confirmDelete(Vault.ID) }`.
- A single `@Presents var destination: Destination.State?` replaces the current
  standalone `alert`. The alert case serves double duty: delete confirmation and
  the existing operation-failed error (an alert with only an OK button and no
  associated `Alert` action).
- **Actions:**
  - `addButtonTapped` → `destination = .form(.init())` (create).
  - `editButtonTapped(Vault)` → `destination = .form(.init(vault:))` (edit).
  - `deleteButtonTapped(Vault)` → `destination = .alert(.confirmDelete(vault))`.
  - `destination(.presented(.alert(.confirmDelete(id))))` → perform the delete
    write, catching failures into the error alert.
  - `operationFailed(String)` → `destination = .alert(errorAlert)`.

Reads flow through `@FetchAll`, so the list refreshes automatically after any
insert/update/delete — no delegate plumbing is needed to pass data back from the
form.

## View / UI

### List rows & swipe actions (`AppView`)

- Rows still show the name with the `"Untitled Vault"` fallback. The old
  `.onDelete` is removed.
- Each row gets `.swipeActions(edge: .trailing, allowsFullSwipe: false)` with two
  **plain** `Button`s (no roles):
  - **Edit** → `.editButtonTapped(vault)`, `.tint(.blue)`.
  - **Delete** → `.deleteButtonTapped(vault)`, `.tint(.red)`.
- `allowsFullSwipe: false` is deliberate — a full swipe must not bypass the
  confirmation.
- The delete swipe button is a plain `Button` tinted red, **not**
  `role: .destructive`.

### Confirmation alert

- Presented via `.alert($store.scope(state: \.destination?.alert, action: \.destination.alert))`.
- Title `"Delete Vault?"`, message naming the vault, a Cancel button, and a
  Delete button. The **alert's** Delete button uses `role: .destructive`
  (standard red alert button + Return-key behavior). The "no `.destructive`" rule
  applies only to the swipe action, not the alert.

### Form sheet (`VaultFormView`)

- Presented via `.sheet($store.scope(state: \.destination?.form, action: \.destination.form))`.
- `NavigationStack { Form { TextField("Name", text: $store.draft.name) } }` with:
  - A navigation title switching between `"New Vault"` / `"Edit Vault"`.
  - A **Cancel** toolbar button that dismisses.
  - A **Save** toolbar button disabled via `isSaveDisabled`.
- Tapping a row outside the swipe does nothing.

## Testing

- New `TestStore`-based tests:
  - Add presents an empty form.
  - Edit presents a form seeded from the vault.
  - Save inserts (create) / updates (edit) and dismisses.
  - Empty (whitespace-only) name keeps Save disabled.
  - Delete presents the confirm alert and deletes only on confirm.
- Existing `SchemaTests` stay as-is.

## Files

- New: `Core/Sources/Features/VaultFormFeature.swift`
- Modified: `Core/Sources/Features/AppFeature.swift`
- New: `Core/Tests/VaultCRUDTests.swift`

## Out of scope

- Things CRUD and the vault → Things drill-down.
