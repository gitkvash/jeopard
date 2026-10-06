import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/responsive.dart';
import '../core/theme.dart';

/// The 6x5 board, in the grammar of the television original: panels of blue
/// light separated by black gutters, values struck into them in gold.
///
/// The details that carry it are specific. Gutters are *black*, not a lighter
/// grey, so each tile reads as its own lit panel. Corners are nearly square --
/// rounding them turns a board into a list of cards. Values are condensed and
/// heavy with a hard shadow, which is the single most recognisable thing on a
/// Jeopardy board and the thing a normal-width font destroys.
class BoardGrid extends StatelessWidget {
  const BoardGrid({
    super.key,
    required this.board,
    required this.onTapTile,
    this.interactive = true,
  });

  final List<BoardColumn> board;
  final void Function(TileView tile) onTapTile;

  /// False for team devices, which see the board but must not drive it.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    if (board.isEmpty) {
      return const SizedBox.shrink();
    }
    final short = context.isShort;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Six columns do not fit across a phone at a width that reads, and a
        // board that scrolls sideways is a board nobody can see all of -- which
        // is the one thing a player looks at it for. So below a width where the
        // names still wrap into words, the columns squeeze to fit and the names
        // turn on their side, where a header's whole height is the line length.
        final slim = constraints.maxWidth < _slimBelow && !short;
        final minColumnWidth = slim ? _slimColumn : _columnMin;
        final needed = board.length * minColumnWidth;
        final width = needed > constraints.maxWidth
            ? needed
            : constraints.maxWidth;

        final headerHeight = slim
            ? _slimHeader
            : short
            ? _shortHeader
            : _headerHeight;
        final gutter = short ? 4.0 : kGutter;

        // One font size for the whole board, measured once. Letting each tile
        // scale its own text costs a layout pass per tile and leaves the digits
        // at thirty slightly different sizes.
        final rows = board.first.tiles.length;
        final columnWidth = width / board.length;
        final rowHeight = rows == 0
            ? 48.0
            : math.max(
                short ? 20.0 : 26.0,
                (constraints.maxHeight - headerHeight - gutter * (rows + 2)) /
                    rows,
              );
        final valueSize = math
            .min(columnWidth * 0.40, rowHeight * 0.62)
            .clamp(14.0, 46.0);

        final grid = Container(
          width: width,
          padding: EdgeInsets.all(gutter),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.85),
                blurRadius: 50,
                offset: const Offset(0, 18),
                spreadRadius: -14,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < board.length; i++) ...[
                if (i > 0) SizedBox(width: gutter),
                Expanded(
                  child: _Column(
                    column: board[i],
                    onTapTile: onTapTile,
                    interactive: interactive,
                    valueSize: valueSize,
                    headerHeight: headerHeight,
                    gutter: gutter,
                    rotateHeader: slim,
                    smallHeader: short,
                  ),
                ),
              ],
            ],
          ),
        );

        return needed > constraints.maxWidth
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: grid,
              )
            : grid;
      },
    );
  }
}

const double _headerHeight = 72;

/// Where a column stops being wide enough to wrap a topic name into words.
const double _columnMin = 104;
const double _slimBelow = 560;

/// Landscape phone: a header is one or two lines, and the tiles need the height.
const double _shortHeader = 40;

/// Upright phone: a rotated name needs length, so the header is tall and the
/// column beneath it is narrow.
const double _slimHeader = 104;
const double _slimColumn = 48;

class _Column extends StatelessWidget {
  const _Column({
    required this.column,
    required this.onTapTile,
    required this.interactive,
    required this.valueSize,
    required this.headerHeight,
    required this.gutter,
    required this.rotateHeader,
    required this.smallHeader,
  });

  final BoardColumn column;
  final void Function(TileView tile) onTapTile;
  final bool interactive;
  final double valueSize;
  final double headerHeight;
  final double gutter;
  final bool rotateHeader;
  final bool smallHeader;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopicPlate(
          name: column.name,
          height: headerHeight,
          rotate: rotateHeader,
          small: smallHeader,
        ),
        for (final tile in column.tiles) ...[
          SizedBox(height: gutter),
          Expanded(
            child: _Tile(
              tile: tile,
              valueSize: valueSize,
              onTap: interactive && tile.available
                  ? () => onTapTile(tile)
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

/// Category plate: Georgian Mtavruli caps on dark slate under a brass rule.
///
/// `toUpperCase` on Georgian yields Mtavruli, which is the script's own display
/// form -- the right answer to "make the headers shout" in a language with no
/// capital letters.
class _TopicPlate extends StatelessWidget {
  const _TopicPlate({
    required this.name,
    required this.height,
    required this.rotate,
    required this.small,
  });

  final String name;
  final double height;

  /// Set on its side, reading bottom to top, for a column too narrow to wrap in.
  final bool rotate;

  /// A landscape phone: less height for the header, so less type in it.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final compact = rotate || small;
    final label = Text(
      name.toUpperCase(),
      textAlign: TextAlign.center,
      maxLines: small ? 2 : 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: JColors.text,
        fontSize: compact ? 10 : 12,
        fontWeight: FontWeight.w700,
        letterSpacing: compact ? 0.2 : 0.6,
        height: rotate ? 1.15 : 1.22,
        shadows: const [
          Shadow(color: Colors.black, offset: Offset(0, 1), blurRadius: 3),
        ],
      ),
    );

    return Container(
      height: height,
      padding: rotate
          ? const EdgeInsets.symmetric(horizontal: 3, vertical: 6)
          : EdgeInsets.symmetric(
              horizontal: small ? 4 : 8,
              vertical: small ? 3 : 6,
            ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF141B3A), Color(0xFF0A0F22)],
        ),
        border: Border(bottom: BorderSide(color: JColors.brass, width: 2)),
      ),
      alignment: Alignment.center,
      child: rotate ? RotatedBox(quarterTurns: 3, child: label) : label,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.valueSize, this.onTap});

  final TileView tile;
  final double valueSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final spent = tile.status == TileStatus.done;
    final inPlay = tile.status == TileStatus.inPlay;

    // Repainting one tile should not repaint the grid: a tile changes on hover,
    // ink and status far more often than the board does.
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // Four stops, not three: the first is the lit top edge of the
            // bevel. On a rounded box this cannot be a border.
            colors: spent
                ? const [Color(0xFF141829), JColors.spent, JColors.spent]
                : inPlay
                ? const [
                    Color(0xFFFFF0C4),
                    JColors.goldBright,
                    JColors.gold,
                    Color(0xFFC99A2E),
                  ]
                : const [
                    Color(0xFF3A56F5),
                    JColors.boardLit,
                    JColors.board,
                    JColors.boardDeep,
                  ],
            stops: spent
                ? const [0, 0.10, 1]
                : inPlay
                ? const [0, 0.10, 0.55, 1]
                : const [0, 0.08, 0.45, 1],
          ),
          borderRadius: BorderRadius.circular(JRadius.tile),
          boxShadow: [
            if (inPlay)
              BoxShadow(
                color: JColors.gold.withValues(alpha: 0.45),
                blurRadius: 34,
                spreadRadius: -8,
              ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            hoverColor: const Color(0x22FFFFFF),
            splashColor: const Color(0x33FFFFFF),
            child: Center(
              child: spent
                  ? const Icon(Icons.check, size: 17, color: Color(0xFF232A40))
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      // A four-digit value in a 48-pixel column is a squeeze
                      // the measured size does not always survive; shrinking
                      // beats clipping a digit off a score.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          tile.value?.toString() ?? '?',
                          maxLines: 1,
                          style: engraved(
                            valueSize,
                            color: inPlay
                                ? const Color(0xFF14120A)
                                : JColors.gold,
                            glow: !inPlay,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
