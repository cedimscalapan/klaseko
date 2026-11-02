/// Geometry of the KlaseKo answer sheet (version 3), in millimetres, measured from the centre of
/// the top-left marker. The printer (pdf_docs.dart) and the scanner (omr.dart) both read this
/// file, so the printed sheet and the reader always agree.
class Pt {
  final double x;
  final double y;
  const Pt(this.x, this.y);
}

class SheetLayout {
  static const int version = 3;

  /// Distance between the centres of the corner markers.
  static const double frameW = 180;
  static const double frameH = 250;

  /// Eight coded markers: four corners, the middle of the left and right edges, and the middle of
  /// the top and bottom edges. Each is a 6 x 6 grid of 1.6 mm cells: a black border and a 4 x 4
  /// pattern that tells the scanner which marker it is and which way is up. Any two visible
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
  static const List<int> markerCodes = [16567, 34220, 26324, 38261, 35351, 50463, 17321, 56728];

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
