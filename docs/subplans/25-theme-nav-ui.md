# 25 — Theme + UI + Navigation

**Tier:** 9 | **Est:** 5 days | **Deps:** Features 13~24 | **Bugs:** BUG-03,09,15

---

提示：包括现在的边栏的小红点数量，之后都需要认真规划，现在的待办的红点错误计数了已过期的任务。

## Current State

| Area | Status |
|------|--------|
| Theme variants | 5 done: system / light / dark / evergreen / liyu (516 lines in `theme.dart`) |
| WIP item hiding | Sidebar marks "(开发中)" — but still visible |
| Page transitions | `_fadePage` (FadeTransition 200ms) — uniform |
| Mobile nav | 4 destinations (dashboard/courses/todo/notes) via `NavigationBar` |
| Dark mode | Exists but untested for contrast |
| Sidebar collapse | Not implemented (230px fixed) |
| Keyboard shortcuts | Not implemented |
| Dashboard cards | Static grid, not customizable |

---

## 1. Theme & Visual

### 1.1 Dark Mode Audit [BUG-15]

- [ ] Check all theme tokens: `onSurface`, `onPrimary`, `onSecondary` contrast ≥ 4.5:1
- [ ] Fix `toast` text color in dark mode
- [ ] Fix sidebar selected state (currently may be low contrast)
- [ ] Fix `label` text on colored backgrounds
- [ ] Test all 5 themes in both light/dark variants

**Files:** `lib/core/config/theme.dart`, `lib/widgets/sidebar.dart`

### 1.2 Component Polish

- [ ] **[BUG-09]** Redesign progress indicator: replace `LinearProgressIndicator` with themed `EvergreenProgress` (uses primary color, animated)
- [ ] **[BUG-03]** Redesign flashcard: nicer flip animation, better typography, consistent card shadow
- [ ] Font fallback: define `TextTheme` with Google Fonts + system CJK fallback
- [ ] Icon audit: replace inconsistent icons with Material Symbols equivalents

**Files:** `lib/widgets/`, `lib/features/wordpecker/widgets/`, `lib/features/tutor/screens/`

### 1.3 WIP Content Gate

- [ ] Create a settings toggle: 「显示开发中功能」(default: off)
- [ ] When off: WIP sidebar items hidden, WIP routes redirect to dashboard
- [ ] When on: shows "(开发中)" items (current behavior)

**Files:** `lib/core/config/app_config.dart`, `lib/widgets/sidebar.dart`, `lib/app.dart`

---

## 2. Interaction

### 2.1 Page Transitions

- [ ] Add `_slidePage` variant: slide + fade for drill-down pages (e.g., detail views)
- [ ] Keep `_fadePage` for top-level tab switches
- [ ] Animate sidebar item selection (color transition)

**File:** `lib/app.dart` (`_fadePage` → add `_slidePage`)

### 2.2 Keyboard Shortcuts

| Shortcut | Action | File |
|----------|--------|------|
| `Ctrl+K` | Global command palette | `lib/widgets/command_palette.dart` (new) |
| `Ctrl+,` | Open settings | `lib/app.dart` |
| `F5` | Refresh current page data | `lib/app.dart` (global hotkey) |
| `Ctrl+1-9` | Navigate to sidebar item by index | `lib/app.dart` |

- [ ] Register global `ShortcutRegistry` in `EvergreenApp`
- [ ] Create `CommandPalette` widget (searchable, fuzzy-match routes + actions)

### 2.3 Form Feedback

- [ ] Audit all `SnackBar` usages: consistent duration, position, color
- [ ] Standardize loading states: `LoadingWidget` + shimmer variant
- [ ] Standardize error states: `ErrorCard` with retry callback

**Files:** `lib/widgets/loading_indicator.dart`, `lib/widgets/error_card.dart`

---

## 3. Navigation

### 3.1 Sidebar Collapse

- [ ] Add collapse button at sidebar bottom
- [ ] Collapsed state: icons-only, 60px wide, tooltip on hover
- [ ] Animate width transition (230px ↔ 60px)
- [ ] Persist state in `SharedPreferences`
- [ ] Mobile: ≤800px auto-collapse (already has `_MobileShell` at 600px)

**Files:** `lib/widgets/sidebar.dart`

### 3.2 Responsive Sizing

- [ ] **[Acceptance]** Window 800px → auto-collapse sidebar
- [ ] Sub-page size audit: calendar, forms, detail views scale to fill
- [ ] Max content width on large screens (>1400px): center with max-width

---

## 4. Global Command Palette

### `Ctrl+K` — New Widget

- [ ] Searchable overlay: routes, tools, recent actions
- [ ] Fuzzy match route names + descriptions
- [ ] Recently used items first
- [ ] Result: navigate to route / execute action

**Files:** `lib/widgets/command_palette.dart` (new), `lib/app.dart` (register shortcut)

---

## Acceptance

- [ ] Dark mode: all text passes WCAG AA (≥4.5:1 contrast)
- [ ] Window 800px → sidebar auto-collapses
- [ ] All sub-pages fit viewport without horizontal scroll
- [ ] `Ctrl+K` opens command palette, navigates to any page
- [ ] WIP items hidden by default (toggle in settings)
