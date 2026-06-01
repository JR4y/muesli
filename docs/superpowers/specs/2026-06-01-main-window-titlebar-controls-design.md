# Main Window Titlebar Controls Design

Date: 2026-06-01
Status: Implemented with native-titlebar constraints
Scope:
- `native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift`
- `native/MuesliNative/Sources/MuesliNativeApp/DashboardRootView.swift`
- new titlebar/AppKit bridge files as needed

## Goal

Give the main window a stable, intentional top chrome layout:

- sidebar toggle always fixed on the left side of the titlebar
- quick note action always fixed on the right side of the titlebar
- no duplicate sidebar buttons
- no toolbar background artifacts around the quick note control
- behavior that remains stable while resizing, collapsing the sidebar, or navigating between app sections

## Problem Summary

The current macOS shell mixes three different layout systems:

1. `NavigationSplitView` injects a native sidebar toggle into the titlebar/toolbar area.
2. SwiftUI `ToolbarItem` placement lets AppKit relocate items based on available width and toolbar heuristics.
3. A content-level top bar can visually stabilize controls, but it cannot replace or suppress the native titlebar controls.

This creates two recurring UX failures:

- the sidebar button is not positionally stable
- any custom sidebar button added inside the app creates duplication with the native one

The recent prototype with a content-level top bar confirmed that fixed layout is easy inside the content area, but it also confirmed that this does not solve the titlebar duplication problem.

## Product Requirements

The final solution must satisfy all of the following:

- exactly one visible sidebar toggle affordance
- sidebar toggle fixed visually on the left side of the titlebar
- quick note fixed visually on the right side of the titlebar
- no dependence on adaptive toolbar relocation for these two controls
- the solution must still feel native on macOS
- the sidebar must still open and close with predictable animation and interaction behavior

## Key Design Decision

Do not keep depending on the titlebar behavior that `NavigationSplitView` automatically injects.

Instead:

- use the real macOS titlebar as the presentation surface
- place custom controls into fixed titlebar regions via AppKit
- control sidebar visibility explicitly from app-owned state instead of relying on the automatic native titlebar button

This is the only direction that can guarantee both fixed positions and no duplicate sidebar toggle.

## Rejected Approaches

### 1. Keep using SwiftUI toolbar placements

Rejected because AppKit will keep adapting placement based on width, titlebar traffic-light spacing, and toolbar heuristics. This is the root cause of the current inconsistency.

### 2. Hide or patch the native sidebar button while keeping `NavigationSplitView` in charge

Rejected as the primary strategy because it is brittle. It relies on fighting framework-owned UI rather than removing the dependency on it.

### 3. Keep a fake top bar inside the content area

Rejected because it cannot remove the native titlebar affordance and therefore cannot eliminate duplication.

## Proposed Architecture

The implementation should be split into three responsibilities.

### 1. Window titlebar controller

Create a small AppKit coordinator attached to the main window.

Responsibilities:

- configure the window for titlebar-integrated content
- install left and right titlebar accessory containers
- host SwiftUI controls inside those containers
- keep the titlebar controls alive across window updates

This controller should be owned by the main window setup in `RecentHistoryWindowController`.

### 2. Titlebar control views

Render the two visible controls as app-owned SwiftUI views hosted in the titlebar.

Left side:

- custom sidebar toggle button
- compact, neutral styling
- fixed width/height so it aligns visually near the traffic lights

Right side:

- quick note button
- visually lighter than the current toolbar pill
- supports a compact treatment if width ever becomes constrained

These controls should not be implemented as `ToolbarItem`s.

### 3. Sidebar visibility bridge

Sidebar visibility should become an explicit part of the app shell rather than something only the system toolbar controls.

Preferred approach:

- replace reliance on `NavigationSplitView`'s automatic titlebar integration
- use an app-controlled shell with explicit sidebar visibility state

Two valid implementation shapes:

- SwiftUI shell based on `HSplitView` or equivalent custom split layout
- AppKit-owned split view controller with SwiftUI-hosted sidebar/detail content

The recommended first implementation is the lighter SwiftUI-owned shell, because the app already manages most navigation state manually and does not appear to require `NavigationSplitView`-specific titlebar behavior.

## Recommended Shell Direction

Use an app-owned split shell instead of `NavigationSplitView` for the main dashboard window.

Why:

- it removes the automatic native sidebar button source entirely
- it gives the app deterministic control over sidebar visibility
- it avoids future fights with toolbar heuristics
- it matches the product goal better than trying to suppress framework-injected chrome

This shell should preserve the current functional structure:

- sidebar content stays `SidebarView`
- detail content stays the existing dashboard/detail routing
- visibility is toggled via app state rather than framework-owned titlebar behavior

## State Model

Introduce explicit window-shell state for sidebar visibility.

Minimum requirement:

- `isSidebarVisible: Bool`

Optional future expansion:

- persisted last-known sidebar width
- collapsed/expanded animation preferences if needed

The sidebar toggle button in the titlebar should read and mutate this state directly.

## Visual Design

### Sidebar button

- compact circular or rounded-square control
- neutral surface treatment
- always left aligned in the titlebar accessory region
- no text label

### Quick note button

- more minimal than the current toolbar version
- preferred default: `+` plus `Nota rapida`
- acceptable fallback: icon-only compact version if future width constraints require it
- accent color remains the visual cue

Implementation note after validation:

- the final shipped compromise for this pass is `+ Nota` at standard dashboard
  widths, with icon-only fallback only for narrower windows
- this is intentionally shorter than the original preference because the native
  titlebar lane clipped attempts to gain extra vertical breathing room through
  larger accessory heights or vertical padding

### Spacing

- left control should visually clear the traffic lights and match macOS titlebar rhythm
- right control should be anchored consistently to the right edge of the titlebar content region
- controls should not shift horizontally when the sidebar opens or closes

## Behavioral Expectations

- clicking the custom sidebar button toggles the sidebar without depending on the native titlebar button
- resizing the window does not swap control order or move the quick note button toward the center
- quick note remains available only in the same product contexts where it is currently intended to appear
- if the sidebar is hidden, the detail content expands naturally without layout tearing

## Planned Code Changes

### Remove prototype content bar

The temporary content-level top bar introduced in `DashboardRootView` should be removed. It was a useful experiment, but it is not the final architecture.

### Main window integration

In `RecentHistoryWindowController`:

- keep `fullSizeContentView` if it helps titlebar integration
- instantiate and retain a titlebar coordinator
- attach titlebar accessory hosting views to the window

### Dashboard shell

In `DashboardRootView`:

- remove the experimental overlay top bar
- replace `NavigationSplitView` with an app-controlled split shell
- bind shell visibility to explicit state

### New support types

The implementation should introduce:

- one coordinator file for titlebar/window integration, preferred name `MainWindowTitlebarController.swift`
- one shell file for the app-owned sidebar/detail layout, preferred name `DashboardSplitShell.swift`

The quick note accessory view can stay inline unless reuse or file size makes extraction worthwhile.

## Risks

### Sidebar shell migration risk

Replacing `NavigationSplitView` can introduce layout regressions if sidebar sizing, minimum widths, or detail resizing are not carefully matched.

### Window lifecycle risk

Titlebar accessory views can be fragile if their coordinator is not retained correctly by the window controller.

### macOS chrome alignment risk

Traffic-light spacing and titlebar insets can vary enough that accessory sizing may need small iteration on real builds.

Observed during implementation:

- AppKit-owned lateral titlebar accessory placement (`.left` / `.right`) gave
  much less vertical flexibility than the early experiments implied
- hosted SwiftUI height and vertical padding changes were not sufficient to
  create more visible breathing room because the native titlebar lane clipped
  the accessory content

### Keyboard/behavior parity risk

If there are any existing shortcuts or responder-chain assumptions tied to `NavigationSplitView`, they must continue to behave correctly after the shell change.

## Non-Goals

This work does not aim to:

- redesign the sidebar itself
- change meeting-detail behavior
- add new note-taking capabilities
- redesign other secondary windows
- generalize all app windows to a shared chrome system

## Verification Expectations

Implementation should be validated against the following:

1. only one sidebar button is visible
2. the sidebar button stays fixed on the left side of the titlebar
3. the quick note button stays fixed on the right side of the titlebar
4. resizing the window does not cause either control to jump positions
5. toggling the sidebar repeatedly does not produce duplicate controls or stale layout
6. the quick note button has no unwanted white toolbar background artifact
7. the shell remains visually consistent with the rest of the app on both light and dark themes

## Rollout Strategy

Implement in two passes:

1. remove the experimental content bar and establish the titlebar accessory structure
2. move sidebar visibility to an app-controlled shell and verify the native duplicate affordance is gone

If pass 1 cannot guarantee elimination of the native duplicate button, do not ship an in-between state. Continue directly to the app-controlled shell in the same implementation branch.
