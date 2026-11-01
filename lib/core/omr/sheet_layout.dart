/// Geometry of the KlaseKo answer sheet, in millimetres, measured from the centre of the
/// top-left corner marker. The printer (pdf_answer_sheet.dart) and the scanner (omr.dart)
/// both read this file, so the printed sheet and the reader always agree.
class Pt {
  final double x;
  final double y;
  const Pt(this.x, this.y);
}

class SheetLayout {
  /// Distance between the centres of the corner markers.
  static const double frameW = 180;
  static const double frameH = 250;

  /// Solid square corner markers.
  static const double marker = 9;

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

  /// Orientation bar printed on the top edge. Its mirror position on the bottom edge stays empty,
  /// which tells the scanner whether the photo is upside down.
  static const double barX0 = 20;
  static const double barX1 = 60;
  static const double barY0 = -1.6;
  static const double barY1 = 1.6;

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
