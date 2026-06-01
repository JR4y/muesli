# Meeting Detail Toolbar Reorg Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize completed meeting detail actions by object while keeping recording and transitional states behaviorally unchanged.

**Architecture:** Keep the current behavior helpers and move completed-state actions into three clearer sections: header context actions, audio actions near the player, and a document toolbar above notes/transcript. Preserve existing live-state control groups and reuse the current button components so the visual language stays aligned with `MeetingsView`.

**Tech Stack:** SwiftUI, Swift Testing, MuesliNativeApp

---

### Task 1: Lock the new completed-state layout rules with tests

**Files:**
- Modify: `native/MuesliNative/Tests/MuesliTests/MeetingDetailViewTests.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/MeetingDetailViewTests.swift`

- [ ] **Step 1: Write failing tests for completed-state toolbar placement helpers**
- [ ] **Step 2: Run the focused meeting detail tests and confirm the new expectations fail**
- [ ] **Step 3: Add the minimal placement helpers in `MeetingDetailView` to satisfy those expectations**
- [ ] **Step 4: Re-run the focused meeting detail tests and confirm they pass**

### Task 2: Recompose the completed meeting detail screen

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingDetailView.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/MeetingDetailViewTests.swift`

- [ ] **Step 1: Simplify completed-state header actions to status plus overflow**
- [ ] **Step 2: Add a completed-state audio action row next to the recording player**
- [ ] **Step 3: Replace the generic completed-state content toolbar with a dedicated document toolbar that owns mode, summarize, template, edit, and copy**
- [ ] **Step 4: Keep recording, note-only, failed, and processing layouts functionally unchanged**

### Task 3: Verify the refactor

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingDetailView.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/MeetingDetailViewTests.swift`

- [ ] **Step 1: Run focused Swift tests for meeting detail view behavior**
- [ ] **Step 2: Run a focused Swift build or broader test command if needed to catch composition regressions**
- [ ] **Step 3: Review the resulting diff for unintended changes outside the intended layout refactor**
