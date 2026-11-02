import 'package:flutter_test/flutter_test.dart';
import 'package:klaseko/core/quiz_import/quiz_parser.dart';

String answers(ParseResult r) => r.items.map((i) => i.answer == null ? '?' : 'ABCD'[i.answer!]).join();

void main() {
  test('neat quiz with an answer key at the end', () {
    final r = parseQuiz('''Grade 8 Mathematics - Quiz 1
Directions: Choose the letter of the correct answer.
1. What is the slope of y = 2x + 3?
a. 3
b. 2
c. -2
d. 1/2
2. Which point lies on the line y = x?
a. (1, 2)
b. (2, 1)
c. (3, 3)
d. (0, 1)
3. The y-intercept of y = -4x + 7 is
A. -4
B. 4
C. 7
D. -7
Answer Key
1. B
2. C
3. C''');
    expect(r.items.length, 3);
    expect(r.items[0].question, 'What is the slope of y = 2x + 3?');
    expect(r.items[1].choices, ['(1, 2)', '(2, 1)', '(3, 3)', '(0, 1)']);
    expect(answers(r), 'BCC');
  });

  test('squashed and inline choices with "Answer:" lines', () {
    final r = parseQuiz('''QUIZ IN SCIENCE 7
1.What is the basic unit of life?a.atom b.cell c.tissue d.organ
Answer: b
2) Which organelle is the powerhouse of the cell? (a) nucleus (b) ribosome (c) mitochondria (d) vacuole
ans: C
3 - Plants make food through
A) respiration   B) photosynthesis
C) digestion   D) transpiration
Answer: B''');
    expect(r.items.length, 3);
    expect(r.items[0].choices, ['atom', 'cell', 'tissue', 'organ']);
    expect(answers(r), 'BCB');
  });

  test('Filipino quiz with Tama o Mali and Susi sa Pagwawasto', () {
    final r = parseQuiz('''PAGSUSULIT SA FILIPINO 8
Panuto: Basahin at piliin ang titik ng tamang sagot.
1. Ano ang tawag sa salitang naglalarawan sa pangngalan?
a. pandiwa b. pang-uri c. pang-abay d. panghalip
2. Alin ang halimbawa ng pandiwa?
a. maganda b. tumakbo c. bahay d. siya
Pagsusulit II. Tama o Mali. Isulat ang Tama kung wasto ang pahayag at Mali kung hindi.
1. Ang pang-uri ay naglalarawan ng pangngalan.
2. Ang "siya" ay isang pandiwa.
3. Ang pangungusap ay may simuno at panaguri.
Susi sa Pagwawasto
Pagsusulit I
1. B
2. B
Pagsusulit II
1. Tama
2. Mali
3. Tama''');
    expect(r.items.length, 5);
    expect(r.items.map((i) => i.type).toList(), ['mc', 'mc', 'tf', 'tf', 'tf']);
    expect(answers(r), 'BBABA');
  });

  test('unnumbered questions with starred and (correct) answers', () {
    final r = parseQuiz('''Which planet is closest to the sun?
a) Venus
*b) Mercury
c) Earth
d) Mars
What gas do plants absorb?
a) Oxygen
b) Nitrogen
c) Carbon dioxide (correct)
d) Hydrogen''');
    expect(r.items.length, 2);
    expect(r.items[0].choices[1], 'Mercury');
    expect(answers(r), 'BC');
  });

  test('OCR text with broken lines, page numbers and a one-line key', () {
    final r = parseQuiz('''Page 1 of 2
ARALING PANLIPUNAN 9
1. Ano ang tawag sa pag-aaral ng
paggamit ng limitadong yaman?
A. Ekonomiks   B. Heograpiya
C. Kasaysayan  D. Sosyolohiya
2. Sino ang tinaguriang Ama ng
Ekonomiks?
A. Karl Marx
B. Adam Smith
C. John Keynes
D. David Ricardo
- 1 -
3 Alin ang pangunahing
suliranin ng ekonomiks?
A. Kakapusan  B. Implasyon  C. Kawalan ng trabaho  D. Utang
1-A, 2-B, 3-A''');
    expect(r.items.length, 3);
    expect(r.items[0].question, 'Ano ang tawag sa pag-aaral ng paggamit ng limitadong yaman?');
    expect(answers(r), 'ABA');
  });

  test('identification is skipped; key on the same line as its heading', () {
    final r = parseQuiz('''Test I. Multiple Choice
1. 2 + 2 =
a. 3 b. 4 c. 5 d. 6
2. 10 / 2 =
a. 2 b. 3 c. 4 d. 5
Test II. Identification
1. What do you call a polygon with 5 sides? ________
2. What is the sum of angles in a triangle? ________
Test III. True or False
1. A square is a rectangle.
2. Zero is a positive number.
Answer key: 1. B 2. D''');
    expect(r.items.length, 4);
    expect(r.skipped, 2);
    expect(answers(r), 'BD??');
  });

  test('bold answer from a Word file', () {
    final r = parseQuiz('1. Capital of the Philippines\na. Cebu\nb. ${markOn}Manila$markOff\nc. Davao\nd. Baguio');
    expect(r.items.single.choices[1], 'Manila');
    expect(answers(r), 'B');
  });
}
