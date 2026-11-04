/// Geometry of the KlaseKo answer sheet, in millimetres. The printer (pdf_docs.dart) and the scanner
/// (omr.dart) both read this file, so the printed sheet and the reader always agree.
///
/// Version 4 sheets have an answer box: small markers around the bubbles and the learner number, so
/// a photo of only that box has everything needed. Version 3 sheets, already printed, have larger
/// markers at the outer edges of the page and the learner number at the top right. The item bubbles
/// sit at the same coordinates in both.
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
  /// least 6 cells in every rotation, so up to 2 smudged cells are still read correctly.
  /// The first eight are the version 3 markers, the last eight the answer box markers.
  static const List<int> markerCodes = [16567, 34220, 26324, 38261, 35351, 50463, 17321, 56728, 56045, 27661, 8202, 60411, 46592, 13035, 39920, 44485];
  static const int areaCodeStart = 8;

  /// The answer box: eight smaller markers in the same arrangement, around the learner number and
  /// the bubbles. Its size follows the number of items, so a short test fills more of the photo.
  static const double areaMarkerCell = 1.2;
  static const double areaMarker = areaMarkerCell * 6;
  static const double areaTop = 62;

  static int columnsFor(int items) => (items + rowsPerColumn - 1) ~/ rowsPerColumn;
  static double areaRight(int items) => columnsFor(items) <= 1 ? 88 : columnX[columnsFor(items) - 1] + 50;
  static double areaBottom(int items) => firstRowY + ((items < rowsPerColumn ? items : rowsPerColumn) - 1) * rowStep + 11;

  static List<Pt> areaMarkerCenters(int items) {
    final r = areaRight(items), b = areaBottom(items);
    return [Pt(0, areaTop), Pt(r, areaTop), Pt(r, b), Pt(0, b), Pt(0, (areaTop + b) / 2), Pt(r, (areaTop + b) / 2), Pt(r / 2, areaTop), Pt(r / 2, b)];
  }

  /// Learner number inside the answer box: a row of tens and a row of ones, digits 0-9 left to right.
  /// Its rows are not on the item rows' spacing, so it is never mistaken for answers.
  static Pt areaIdBubble(int digitColumn, int digit) => Pt(22 + digit * 6.4, digitColumn == 0 ? 73 : 80.3);

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
