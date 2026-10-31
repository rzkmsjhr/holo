# Mobile Architecture & Implementation Blueprint: Pulse Audio

This document specifies the exact component architecture, gesture handlers, state models, and design tokens for implementing **Pulse Audio** across **Flutter** and **Kotlin Multiplatform (Compose Multiplatform)** for iOS and Android.

---

## 1. Design Tokens & Theme Mapping

### Color System
```
Token Name          Dark Hex    Light Hex   Usage / Purpose
-----------------------------------------------------------------------------
primary             #FF5416     #FF5416     Solar Ember: Primary play CTA, scrubber fill, active tab
primaryContainer    #261208     #FFEBE3     Tonal card container, subtle button backgrounds
secondary           #5A32A3     #5A32A3     Night Indigo: Album cover depth, secondary chips
accent              #CCFF00     #CCFF00     Acid Chartreuse: Hi-Res FLAC badge, live scrub head
background          #0A0C10     #F6F7F9     Canvas surface
surface             #14171F     #FFFFFF     Elevated card surface, mini player body
surfaceElevated     #1D212C     #ECEFF4     Quick jump tiles, search inputs, sheet background
borderSubtle        #222736     #E2E5EB     Hairline dividers, card outlines
textPrimary         #FFFFFF     #11141A     High-contrast titles, song names
textSecondary       #8F9CAE     #5C6474     Artist names, playlist metadata
textTertiary        #606B7D     #848D9E     Timestamps, inactive icons, duration labels
```

---

## 2. Screen 1: Home Screen

### Layout Structure
- **Root**: `CustomScrollView` (Flutter) / `LazyColumn` (Jetpack Compose).
- **Header**:
  - Greeting text ("Good evening") with user avatar and theme toggle.
  - Sticky or pinned app bar with zero elevation.
- **Section 1: Quick Jump 6-Grid ("Jump Back In")**:
  - Two columns, three rows.
  - Each item: 56dp height card with 48dp album thumbnail, bold 13sp title, and 1-tap instant play button.
- **Section 2: "Made For You" Carousel**:
  - Horizontal scrolling list with snap physics (`PageScrollPhysics` or `SnappingScrollPhysics`).
  - Card dimensions: 156dp width x 210dp height.
  - 14dp rounded corner artwork with top-left category badge (`Daily Mix`, `Lossless`).
- **Section 3: "Popular Near You" Heavy Rotation**:
  - Standard vertical list rows: 48dp thumbnail, track title, artist name, explicit badge `[E]`, and duration (`3:34`).

### Flutter Widget Tree
```dart
CustomScrollView(
  physics: const BouncingScrollPhysics(),
  slivers: [
    SliverAppBar(
      floating: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Good evening", style: theme.textTheme.headlineSmall),
          Text("32 new releases tailored for your taste", style: theme.textTheme.bodySmall),
        ],
      ),
      actions: [
        IconButton(icon: Icon(Icons.dark_mode_outlined), onPressed: toggleTheme),
        IconButton(icon: Icon(Icons.notifications_none), onPressed: () {}),
      ],
    ),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(
        child: Text("Jump Back In", style: theme.textTheme.titleMedium),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => QuickJumpCard(item: recentItems[i]),
          childCount: 6,
        ),
      ),
    ),
    SliverToBoxAdapter(
      child: HorizontalSnapCarousel(items: dailyMixes),
    ),
    SliverPadding(
      padding: const EdgeInsets.only(bottom: 120), // Bottom padding for MiniPlayer
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => TrackListTile(track: topTracks[i]),
          childCount: topTracks.length,
        ),
      ),
    ),
  ],
)
```

---

## 3. Screen 2: Now Playing (Gesture-Reactive Sheet)

### Layout & Gestures
1. **Swipe Down to Collapse**:
   - In Flutter: `DraggableScrollableSheet` with `snap: true`, `snapSizes: [0.0, 1.0]`, or custom `GestureDetector` tracking `onVerticalDragUpdate` and `onVerticalDragEnd`.
   - In Kotlin Compose: `ModalBottomSheet` with `rememberModalBottomSheetState(skipPartiallyExpanded = true)`.
2. **Interactive Audio Scrubber**:
   - Custom `Slider` with custom `SliderComponentShape` (pill or 16dp circular thumb).
   - Draggable scrubber thumb responds with haptic feedback (`HapticFeedback.selectionClick()` on Flutter, `LocalHapticFeedback.current.performHapticFeedback` on Compose).
3. **Artwork Ambient Backlight**:
   - `Container` with `BoxDecoration` utilizing `radial-gradient` blurred with `ImageFiltered` / `BackdropFilter` (Flutter) or `Modifier.blur(40.dp)` (Compose).
4. **Fluid Equalizer Bars**:
   - Row of 24 vertical bars animated via `AnimationController` / `infiniteRepeatable` sine oscillations.
5. **Transport Controls**:
   - 72dp Solar Ember primary circular Play/Pause button with scale press physics (`scale(0.92)`).
   - Secondary shuffle, repeat, previous, next icon buttons with 48dp minimum touch target.

### Kotlin Jetpack Compose Implementation
```kotlin
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NowPlayingSheet(
    track: Track,
    isPlaying: Boolean,
    progressMs: Long,
    durationMs: Long,
    onPlayPause: () -> Unit,
    onSeek: (Long) -> Unit,
    onDismiss: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface)
            .statusBarsPadding()
            .navigationBarsPadding()
            .pointerInput(Unit) {
                detectVerticalDragGestures { _, dragAmount ->
                    if (dragAmount > 20) onDismiss()
                }
            }
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Drag Pill Handle
        Box(
            modifier = Modifier
                .padding(vertical = 12.dp)
                .width(44.dp)
                .height(5.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.outlineVariant)
        )

        // Top Context Bar
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onDismiss) {
                Icon(Icons.Default.KeyboardArrowDown, contentDescription = "Collapse")
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("PLAYING FROM PLAYLIST", style = MaterialTheme.typography.labelSmall)
                Text(track.album, style = MaterialTheme.typography.titleSmall)
            }
            IconButton(onClick = { /* Options menu */ }) {
                Icon(Icons.Default.MoreHoriz, contentDescription = "Options")
            }
        }

        Spacer(modifier = Modifier.height(20.dp))

        // Ambient Artwork Container
        Box(
            modifier = Modifier
                .size(310.dp)
                .clip(RoundedCornerShape(28.dp))
                .shadow(18.dp, RoundedCornerShape(28.dp)),
            contentAlignment = Alignment.Center
        ) {
            AsyncImage(
                model = track.coverUrl,
                contentDescription = track.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Title + Heart
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(track.title, style = MaterialTheme.typography.headlineSmall, maxLines = 1)
                Text(track.artist, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onClick = { /* Toggle Favorite */ }) {
                Icon(Icons.Default.FavoriteBorder, contentDescription = "Favorite")
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Interactive Timeline Scrubber
        Slider(
            value = progressMs.toFloat(),
            onValueChange = { onSeek(it.toLong()) },
            valueRange = 0f..durationMs.toFloat(),
            colors = SliderDefaults.colors(
                thumbColor = Color.White,
                activeTrackColor = Color(0xFFFF5416),
                inactiveTrackColor = MaterialTheme.colorScheme.outlineVariant
            )
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(formatTime(progressMs), style = MaterialTheme.typography.bodySmall)
            Text("-${formatTime(durationMs - progressMs)}", style = MaterialTheme.typography.bodySmall)
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Transport Controls
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = { /* Shuffle */ }) {
                Icon(Icons.Default.Shuffle, contentDescription = "Shuffle")
            }
            IconButton(onClick = { /* Previous */ }) {
                Icon(Icons.Default.SkipPrevious, contentDescription = "Previous", modifier = Modifier.size(36.dp))
            }
            // Primary Play Button
            FilledIconButton(
                onClick = onPlayPause,
                modifier = Modifier.size(72.dp),
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = Color(0xFFFF5416))
            ) {
                Icon(
                    imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = if (isPlaying) "Pause" else "Play",
                    tint = Color(0xFF0A0C10),
                    modifier = Modifier.size(36.dp)
                )
            }
            IconButton(onClick = { /* Next */ }) {
                Icon(Icons.Default.SkipNext, contentDescription = "Next", modifier = Modifier.size(36.dp))
            }
            IconButton(onClick = { /* Repeat */ }) {
                Icon(Icons.Default.Repeat, contentDescription = "Repeat")
            }
        }
    }
}
```

---

## 4. Screen 3: Library & List (Dual Mode: Saved vs Queue)

### Dual-Segment Architecture
1. **Segmented Control**:
   - `Saved Playlists`: Curated collections, albums, downloaded songs.
   - `Playing Queue (Up Next)`: Live queue with reordering drag handles and swipe-to-dismiss gesture.
2. **Filter Chips**:
   - `All`, `Playlists`, `Albums`, `Artists`, `Downloaded`.
   - Pill chips with 32dp height and tactile press animation.
3. **Queue Gestures**:
   - In Flutter: `Dismissible` widget wrapping each queue item with `direction: DismissDirection.endToStart` and a vibrant red delete action background. Reorderable via `ReorderableListView`.
   - In Compose: `SwipeToDismissBox` with `rememberSwipeToDismissBoxState()` and reorderable list via `Modifier.draggable` or reorderable library.

---

## 5. Persistent Floating Mini-Player

### Architecture
- Positioned above the `BottomNavigationBar` via a `Stack`.
- Height: 56dp.
- Margins: 12dp horizontal, 8dp above bottom bar.
- Background: Glassmorphic blur (`BackdropFilter` with `sigmaX: 16, sigmaY: 16` in Flutter).
- Gestures:
  - Tap: Expands `NowPlayingSheet`.
  - Swipe Up: Expands `NowPlayingSheet`.
  - Play/Pause button: Dispatches playback state without triggering sheet expansion.

---

## 6. Audio Service & State Management

### Flutter Architecture
- **Audio Engine**: `just_audio` + `audio_service` (for native iOS Lock Screen & Android Auto MediaSession integration).
- **State Management**: `flutter_bloc` / `riverpod`:
  - `AudioPlayerBloc`: Manages `PlayerState`, `currentTrack`, `position`, `duration`, `bufferedPosition`, `isShuffled`, `repeatMode`.
  - Emits immutable `AudioState` to ensure 60fps / 120fps UI updates.

### Kotlin Multiplatform Architecture
- **Audio Engine**: Android `androidx.media3.exoplayer` + iOS `AVPlayer` wrapped in a KMP common `AudioPlayer` interface.
- **State Management**: Kotlin Coroutines `StateFlow<PlaybackState>` observed in Compose via `collectAsStateWithLifecycle()`.
