/// Geometry of the KlaseKo answer sheet, in millimetres. The printer (pdf_docs.dart) and the scanner
/// (omr.dart) both read this file, so the printed sheet and the reader always agree.
///
/// Version 4 sheets have an answer box ([BoxLayout]): small markers around the bubbles and the learner
/// number, so a photo of only that box has everything needed. It comes in two sizes, a full page and
/// a quarter of a page. Version 3 sheets, already printed, have larger markers at the outer edges of
/// the page and the learner number at the top right; their item bubbles sit where the full box's do.
class Pt {
  final double x;
  final double y;
  const Pt(this.x, this.y);
}

class SheetLayout {
  static const int version = 4;

  /// Distance between the centres of the corner markers.
  static const double frameW = 180;
  static const double frameH = 250;

  /// Version 3: eight coded markers: four corners, the middle of the left and right edges, and the
  /// middle of the top and bottom edges. Each is a 6 x 6 grid of 1.6 mm cells: a black border and a
  /// 4 x 4 pattern that tells the scanner which marker it is and which way is up. Any two visible
  /// markers are enough to read the sheet.
  static const double markerCell = 1.6;
  static const double marker = markerCell * 6;
  static const List<Pt> markerCenters = [
    Pt(0, 0),
    Pt(frameW, 0),
    Pt(frameW, frameH),
    Pt(0, frameH),
    Pt(0, frameH / 2),
    Pt(frameW, frameH / 2),
    Pt(frameW / 2, 0),
    Pt(frameW / 2, frameH),
  ];

  /// 16-bit patterns (row by row, top-left first, 1 = black). They differ from each other in at
  /// least 5 cells in every rotation, so up to 2 smudged cells are still read correctly.
  /// Eight each: version 3 markers, full answer box markers, 1/4 sheet answer box markers.
  static const List<int> markerCodes = [
    16567, 34220, 26324, 38261, 35351, 50463, 17321, 56728,
    56045, 27661, 8202, 60411, 46592, 13035, 39920, 44485,
    18585, 35360, 7850, 20771, 4598, 33532, 65227, 45022,
  ];
  static bool markerBit(int id, int row, int col) => (markerCodes[id] >> (15 - (row * 4 + col))) & 1 == 1;

  static const int maxItems = 60;
  static const int rowsPerColumn = 20;
  static const int choices = 4;

  static const double bubbleR = 2.6;
  static const List<double> columnX = [6, 66, 126];
  static const double firstRowY = 92;
  static const double rowStep = 7.8;
  static const double choiceX0 = 12;
  static const double choiceStep = 9;

  /// Learner number: two digit columns (tens, ones), digits 0-9 top to bottom.
  static const double idX0 = 150;
  static const double idStep = 11;
  static const double idY0 = 16;
  static const double idRowStep = 6.4;
  static const double idR = 2.4;

  static Pt itemBubble(int item, int choice) {
    final col = item ~/ rowsPerColumn;
    final row = item % rowsPerColumn;
    return Pt(columnX[col] + choiceX0 + choice * choiceStep, firstRowY + row * rowStep);
  }

  static Pt itemLabel(int item) {
    final col = item ~/ rowsPerColumn;
    final row = item % rowsPerColumn;
    return Pt(columnX[col] + 4, firstRowY + row * rowStep);
  }

  static Pt idBubble(int digitColumn, int digit) => Pt(idX0 + digitColumn * idStep, idY0 + digit * idRowStep);
}

/// The answer box of a version 4 sheet, in millimetres. Its size follows the number of items, so a
/// short test fills more of the photo. The scanner reads sizes from the markers, so a sheet printed
/// slightly larger or smaller still reads correctly.
class BoxLayout {
  const BoxLayout({
    required this.codeStart,
    required this.markerCell,
    required this.columnX,
    required this.rights,
    required this.rowsPerColumn,
    required this.maxItems,
    required this.top,
    required this.firstRowY,
    required this.rowStep,
    required this.choiceX0,
    required this.choiceStep,
    required this.bubbleR,
    required this.labelRight,
    required this.bottomGap,
    required this.idLabelX,
    required this.idX0,
    required this.idStep,
    required this.idR,
    required this.tensY,
    required this.onesY,
    required this.letterFont,
    required this.labelFont,
    required this.glyphScale,
  });

  final int codeStart;
  final double markerCell;
  final List<double> columnX;

  /// Right marker position for one, two and three columns of items.
  final List<double> rights;
  final int rowsPerColumn;
  final int maxItems;
  final double top;
  final double firstRowY;
  final double rowStep;
  final double choiceX0;
  final double choiceStep;
  final double bubbleR;

  /// Where the printed item number ends, measured from its column.
  final double labelRight;
  final double bottomGap;
  final double idLabelX;
  final double idX0;
  final double idStep;
  final double idR;

  /// Rows of the learner number. They are off the item rows' spacing, so they are never taken for answers.
  final double tensY;
  final double onesY;
  final double letterFont;
  final double labelFont;

  /// Size of the printed letters compared with the full sheet's.
  final double glyphScale;

  static const full = BoxLayout(
    codeStart: 8,
    markerCell: 1.2,
    columnX: [6, 66, 126],
    rights: [88, 116, 176],
    rowsPerColumn: 20,
    maxItems: 60,
    top: 62,
    firstRowY: 92,
    rowStep: 7.8,
    choiceX0: 12,
    choiceStep: 9,
    bubbleR: 2.6,
    labelRight: 6,
    bottomGap: 11,
    idLabelX: 6,
    idX0: 22,
    idStep: 6.4,
    idR: 2.4,
    tensY: 73,
    onesY: 80.3,
    letterFont: 6.5,
    labelFont: 7.5,
    glyphScale: 1,
  );

  /// A quarter of a page: 15 rows and up to three columns, with bubbles still large enough to shade.
  static const quarter = BoxLayout(
    codeStart: 16,
    markerCell: 1.0,
    columnX: [3, 32, 61],
    rights: [61, 64, 93],
    rowsPerColumn: 15,
    maxItems: 45,
    top: 0,
    firstRowY: 19.5,
    rowStep: 5,
    choiceX0: 10.5,
    choiceStep: 5.2,
    bubbleR: 1.9,
    labelRight: 7.3,
    bottomGap: 5.5,
    idLabelX: 3.6,
    idX0: 13,
    idStep: 4.7,
    idR: 1.7,
    tensY: 7,
    onesY: 12,
    letterFont: 5,
    labelFont: 5.5,
    glyphScale: 0.77,
  );

  static const all = [full, quarter];

  double get marker => markerCell * 6;

  int columnsFor(int items) => (items + rowsPerColumn - 1) ~/ rowsPerColumn;

  double right(int items) => rights[(columnsFor(items) - 1).clamp(0, rights.length - 1).toInt()];

  double bottom(int items) => firstRowY + ((items < rowsPerColumn ? items : rowsPerColumn) - 1) * rowStep + bottomGap;

  /// Four corners, the middle of the left and right edges, the middle of the top and bottom edges.
  List<Pt> markers(int items) {
    final r = right(items), b = bottom(items);
    return [Pt(0, top), Pt(r, top), Pt(r, b), Pt(0, b), Pt(0, (top + b) / 2), Pt(r, (top + b) / 2), Pt(r / 2, top), Pt(r / 2, b)];
  }

  Pt item(int i, int choice) => Pt(columnX[i ~/ rowsPerColumn] + choiceX0 + choice * choiceStep, firstRowY + (i % rowsPerColumn) * rowStep);

  double labelRightAt(int i) => columnX[i ~/ rowsPerColumn] + labelRight;

  /// Learner number: a row of tens and a row of ones, digits 0-9 left to right.
  Pt id(int digitColumn, int digit) => Pt(idX0 + digit * idStep, digitColumn == 0 ? tensY : onesY);
}
