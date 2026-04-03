# Plan: Dynamic Model Discovery at Application Startup

## Problem

LlamaBarn currently only displays models that match hardcoded catalog entries in `Catalog+Data.swift`. Any GGUF files in `~/.cache/huggingface/hub/` that don't match catalog entries are either:
- Skipped silently (if GGUF header parsing fails)
- Only partially discovered (dynamic entries exist but are not fully integrated into the UI)

Users see fewer models in the UI than actually exist in their HF cache.

## Current Architecture

### Model Loading Flow
1. `ModelManager.init()` → `refreshDownloadedModels()` on app startup
2. `refreshDownloadedModels()` scans:
   - Legacy dir (`~/.llamabarn/`) — flat `.gguf` files matching catalog
   - HF cache (`~/.cache/huggingface/hub/`) — via `HFCache.scanForModels(cacheDir, catalog: allCatalogModels)`
3. `HFCache.scanForModels()` returns two things:
   - `[String: ResolvedPaths]` — matched catalog entries
   - `[CatalogEntry]` — dynamic entries (unrecognized GGUF files)
4. **Bug**: `ModelManager.refreshDownloadedModels()` line 394 only uses catalog-matched models:
   ```swift
   let downloaded = allCatalogModels.filter { finalResolved[$0.id] != nil }
   ```
   Dynamic entries from `hfResults.dynamicEntries` are completely ignored.

### Key Files
- `LlamaBarn/Models/ModelManager.swift` — model state management
- `LlamaBarn/System/HFCache.swift` — HF cache scanning (already has dynamic discovery logic)
- `LlamaBarn/System/GGUFParser.swift` — GGUF header parsing
- `LlamaBarn/Catalog/CatalogEntry.swift` — model entry struct
- `LlamaBarn/Menu/MenuController.swift` — UI menu construction
- `LlamaBarn/Catalog/CatalogEntry+Compatibility.swift` — memory compatibility checks

## Goal

Show ALL valid GGUF models from the HF cache at startup, whether or not they're in the hardcoded catalog. Dynamic models should support the same features as catalog models: compatibility checking, context tier selection, loading/unloading, and deletion.

## Implementation Plan

### Phase 1: Fix Dynamic Entry Integration (Core)

#### 1.1 Update `ModelManager.refreshDownloadedModels()`
**File**: `LlamaBarn/Models/ModelManager.swift`
**Lines**: 335-400

Change `refreshDownloadedModels()` to include dynamic entries in the downloaded models list:

```swift
// Current (line 387-394):
let hfResults = HFCache.scanForModels(cacheDir: hfCacheDir, catalog: allCatalogModels)
for (modelId, paths) in hfResults {
  allResolved[modelId] = paths
}
let finalResolved = allResolved
let downloaded = allCatalogModels.filter { finalResolved[$0.id] != nil }

// New:
let (hfResolved, hfDynamicEntries) = HFCache.scanForModels(cacheDir: hfCacheDir, catalog: allCatalogModels)
for (modelId, paths) in hfResolved {
  allResolved[modelId] = paths
}

// Store dynamic entries so they can be displayed
let finalResolved = allResolved
let catalogDownloaded = allCatalogModels.filter { finalResolved[$0.id] != nil }
let downloaded = catalogDownloaded + hfDynamicEntries
```

Also need to store dynamic entries separately so they're not confused with catalog models during operations like deletion or download.

#### 1.2 Add dynamic models storage to `ModelManager`
**File**: `LlamaBarn/Models/ModelManager.swift`

Add a new property:
```swift
var dynamicModels: [CatalogEntry] = []
```

Update `refreshDownloadedModels()` to populate this:
```swift
let (hfResolved, hfDynamicEntries) = HFCache.scanForModels(...)
// ...
await MainActor.run {
  Self.updateDownloadedModels(downloaded, resolved: finalResolved, dynamic: hfDynamicEntries)
}
```

Update `updateDownloadedModels()`:
```swift
private static func updateDownloadedModels(
  _ models: [CatalogEntry], resolved: [String: ResolvedPaths], dynamic: [CatalogEntry]
) {
  let manager = ModelManager.shared
  manager.downloadedModels = models.sorted(by: CatalogEntry.displayOrder(_:_:))
  manager.dynamicModels = dynamic.sorted(by: CatalogEntry.displayOrder(_:_:))
  manager.resolvedPaths = resolved
  // ...
}
```

Update `managedModels` computed property to include dynamic models:
```swift
var managedModels: [CatalogEntry] {
  (downloadedModels + dynamicModels + downloadingModels).sorted(by: CatalogEntry.displayOrder(_:_:))
}
```

### Phase 2: Enhance Dynamic Entry Quality

#### 2.1 Improve `GGUFParser` metadata extraction
**File**: `LlamaBarn/System/GGUFParser.swift`

The parser already extracts key metadata. Consider adding:
- `general.quantization` — if present in GGUF header
- Better architecture-to-family-name mapping (e.g., `llama` → "LLaMA", `qwen2` → "Qwen2")
- `general.type` — if present

#### 2.2 Add compatibility checking for dynamic models
**File**: `LlamaBarn/Catalog/CatalogEntry+Compatibility.swift`

Dynamic entries already have `parameterCount`, `fileSize`, `ctxWindow`, and `overheadMultiplier` set, so `isCompatible()` and `usableCtxWindow()` should work. Verify this is the case.

The key fields needed for compatibility:
- `fileSize` — ✅ set from GGUF header
- `ctxWindow` — ✅ set from `llama.context_length` (defaults to 8192)
- `parameterCount` — ✅ set from `general.parameter_count`
- `overheadMultiplier` — ✅ set to 1.1 (reasonable default)
- `ctxBytesPer1kTokens` — ⚠️ hardcoded to 64KB, may vary by architecture

#### 2.3 Improve `ctxBytesPer1kTokens` estimation
**File**: `LlamaBarn/System/HFCache.swift` line 390

The current default of 64KB per 1K tokens is generic. Consider estimating based on parameter count:
- Small models (<3B): ~16KB per 1K tokens
- Medium models (3B-13B): ~32KB per 1K tokens  
- Large models (13B-70B): ~64KB per 1K tokens
- XL models (>70B): ~128KB per 1K tokens

Or extract `llama.embedding_length` and `llama.attention.head_count` from GGUF header for accurate calculation.

### Phase 3: UI Integration

#### 3.1 Update `MenuController` to show dynamic models
**File**: `LlamaBarn/Menu/MenuController.swift`

Dynamic models should appear in the "Installed" section alongside catalog models. The current code at lines 250-273 already uses `modelManager.managedModels`, which will include dynamic models after Phase 1.

Verify that:
- Dynamic models display correctly in the menu
- Context tier selection works for dynamic models
- Delete functionality works for dynamic models
- Loading/unloading works for dynamic models

#### 3.2 Add visual distinction for dynamic models
**File**: `LlamaBarn/Menu/MenuController.swift`

Consider adding a subtle indicator (e.g., different icon or badge) to distinguish dynamic models from catalog models. This helps users understand which models have full metadata vs. dynamically discovered ones.

#### 3.3 Update models.ini generation
**File**: `LlamaBarn/Models/ModelManager.swift` lines 268-332

The `generateModelsFileContent()` method iterates `downloadedModels`. Update it to also include `dynamicModels`:

```swift
for model in downloadedModels + dynamicModels {
  guard let tier = model.effectiveCtxTier else { continue }
  // ... rest of the logic
}
```

### Phase 4: Edge Cases and Robustness

#### 4.1 Handle GGUF parsing failures gracefully
**File**: `LlamaBarn/System/HFCache.swift` line 375

Currently, GGUF parsing failures are silently skipped. Consider:
- Logging failed parses with `os.Logger`
- Showing a count of skipped files in Settings for debugging

#### 4.2 Handle multi-file GGUF shards for dynamic models
**File**: `LlamaBarn/System/HFCache.swift` lines 364-409

The current dynamic discovery only handles single-file GGUFs. Multi-shard models (e.g., `00001-of-00003.gguf`) need:
- Detection of shard patterns in filenames
- Aggregation of file sizes across shards
- Validation that all shards are present

#### 4.3 Handle mmproj files for dynamic vision models
**File**: `LlamaBarn/System/HFCache.swift`

Vision models require mmproj files. For dynamic discovery:
- Scan for `mmproj*.gguf` files in the same snapshot directory
- Link them to the corresponding model entry
- Set `mmprojUrl` appropriately

#### 4.4 Prevent duplicate dynamic entries
**File**: `LlamaBarn/System/HFCache.swift` lines 364-409

The current code already checks:
```swift
if result.values.contains(where: { $0.modelFile == filePath }) {
  continue
}
```

But this only checks within a single snapshot. If the same GGUF exists in multiple snapshots/commits, it could create duplicates. Add a check across all snapshots.

### Phase 5: Testing

#### 5.1 Manual testing scenarios
- Place a known GGUF file in HF cache that's NOT in the catalog
- Verify it appears in the Installed section
- Verify it can be loaded and used
- Verify it can be deleted
- Verify context tier selection works
- Verify models.ini is updated correctly

#### 5.2 Edge cases to test
- Corrupted GGUF files (should be skipped)
- Non-GGUF files (should be ignored)
- Multi-shard models
- Vision models with mmproj files
- Very large models that don't fit in memory
- Models with unusual architectures

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Dynamic models lack metadata (serverArgs, etc.) | Medium | Use sensible defaults; allow manual config |
| GGUF parsing is slow for many files | Low | Parse only `.gguf` files; cache results |
| Dynamic models break models.ini format | Medium | Validate generated INI before writing |
| Memory calculations inaccurate for unknown architectures | Medium | Use conservative defaults; allow override |

## Dependencies

- No new external dependencies required
- Uses existing `GGUFParser`, `HFCache`, and `CatalogEntry` infrastructure

## Rollout Strategy

1. **Phase 1** is the critical fix — dynamic entries are already discovered but ignored
2. **Phases 2-3** improve the quality and visibility of dynamic models
3. **Phase 4** handles edge cases for robustness
4. Each phase can be merged independently; earlier phases provide immediate value
