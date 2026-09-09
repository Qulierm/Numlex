# Справочник синтаксиса Numlex

## Область документа

Документ описывает текущую ветку `main` (после R89). Опубликованные релизы могут
отставать от `main`: поведение, описанное здесь, не является частью конкретного
релиза.

Источники истины — регистры в исходном коде (`MathFunctions.table`,
`PercentageGrammar`, `NaturalCalculation`, `DateArithmetic`, `UnitCatalog`,
`FiatCurrencies`, `CurrencyPresentation`, `CookingDensities`, `NumberPattern`,
`IntegerBases` и др.) и канонические тесты. README описывает только возможности
кратко и может не покрывать весь синтаксис.

## Содержание

- [Область документа](#область-документа)
- [Обозначения](#обозначения)
- [Модель листа](#модель-листа)
- [Числовые литералы](#числовые-литералы)
- [Операторы](#операторы)
- [Встроенные функции (23)](#встроенные-функции-23)
- [Системы счисления](#системы-счисления)
- [Проценты](#проценты)
- [Естественные деньги](#естественные-деньги)
- [Команда `total`](#команда-total)
- [Даты](#даты)
- [Единицы](#единицы)
- [Приложение: полный каталог невалютных единиц](#приложение-полный-каталог-невалютных-единиц)
- [Валюты](#валюты)
- [Сетевые запросы](#сетевые-запросы)
- [Региональные форматы чисел](#региональные-форматы-чисел)
- [Отображение чисел](#отображение-чисел)
- [Answer Tokens](#answer-tokens)
- [Пользовательские константы](#пользовательские-константы-settings--constants)
- [Сводный алфавитный индекс ключевых слов](#сводный-алфавитный-индекс-ключевых-слов)
- [Что НЕ является синтаксисом](#что-не-является-синтаксисом)

## Обозначения

| Обозначение | Значение |
|---|---|
| `<expr>` | любое арифметическое выражение |
| `<value>` | числовое значение |
| `<unit>` | единица измерения или выражение над единицами |
| `<place>` | свободное текстовое имя места (до 100 символов) |
| `<Answer Token>` | вставленный токен ответа (маркер U+FFFC) |

Слова синтаксиса — английские. Там, где это указано, они не зависят от регистра
(`OF` = `of`, `Per Day` = `per day`). Язык интерфейса и региональный формат чисел
— независимые настройки: локализация не меняет синтаксис.

## Модель листа

Одна логическая строка → один результат в правом столбце. Строки оцениваются
сверху вниз; ниже объявленное имя видно в последующих строках.

### Формы строк

| Форма | Пример | Поведение |
|---|---|---|
| Пустая строка | | Нет результата |
| Заголовок | `# Расчёт зарплаты` | Визуальный заголовок, в расчёте пропускается |
| Комментарий | `// итог за неделю` | Пропускается (заголовок листа при первой `//`-строке) |
| Подпись | `Итог:` | Строка, оканчивающаяся двоеточием, — подпись-разделитель; оценивается как пропуск |
| Именованное значение | `base pay = 4500` | `<name> = <expr>`: имя — 1–6 ASCII-слов (или одно токен-слово), ≤ 40 символов, первое слово начинается с буквы, без операторов; значение неизменно для листа |
| Встроенная сумма | `total` | Команда (без регистра): суммирует eligible-строки секции, см. раздел «total» |
| Числовое выражение | `12 + 30 × 2` | См. «Операторы» |
| Проценты и деньги | `15% of 490`, `$24 per day` | Раздел «Проценты, деньги, total, даты» |
| Единицы | `10 km to m`, `90 km per 3 day` | Раздел «Единицы» |
| Целочисленные базы | `0x1F`, `255 as hex` | Раздел «Системы счисления» |
| Даты | `May 5 + 3 weeks` | Раздел «Даты» |
| Сеть | `weather in London`, `distance between …` | Раздел «Сетевые запросы» |
| Обычный текст | `закупил кабель` | Тихо: результата нет, строчка не «догадывается» |

Важно: строка, которая содержит маркер валюты (`$`, `€`, `100 USD` …), обязана
полностью распарситься как денежное выражение — иначе скрытая ошибка, «догадки»
нет. Аналогично строки «похожие на дату» и «похожие на вызов функции»
(`имя(`) строгие: неизвестная функция — ошибка, а не группа в скобках.

## Числовые литералы

- Десятичный разделитель: `.` или `,` (по региональному формату, раздел
  «Региональные форматы»).
- Разделители тысяч в вводе: `1,234` → `1234`, `1 234` (зависит от формата);
  внутри вызовов функций запятая — разделитель аргументов, см. там.
- Научные: `1.5e6`, `2E-3`.
- Компактные суффиксы (сразу после числа, БЕЗ пробела): `1.5M` = 1 500 000;
  допустимые суффиксы `k K M G T P`. **Внимание:** `5m` — это 5 000 000 (пять
  миллионов), а не пять метров; метра требует пробела: `5 m`.
- Пробелы вокруг операторов произвольны; скобки `( )`; унарные `+` и `-`.
- Quick-операторы (настройка «Быстрые операторы», только когда включены и только
  между двумя цифрами, внутри идентификаторов не действуют):
  `p`→`+`, `m`→`−`, `x`→`×`, `d`→`÷`. Литерал `0x…` никогда не превращается в
  умножение.

## Операторы

Общий (общетиповой) приоритет, от низшего к высшему:

`if … then … else …` (правая ассоциативность) < `or` / `||` < `and` / `&&` <
`not` / `!` < `==` `!=` < `<` `<=` `>` `>=` < `+` `−` (левая) < `*` `×` `/` `÷`
(левая) < `^` (степень, правая) < унарные < первичные (литералы, скобки,
вызовы функций, `%` и `x` как постфиксы, `of` — инфикс отношения).

| Оператор | Смысл | Примечание |
|---|---|---|
| `+` `−` | сложение/вычитание | в аддитивном контексте правый «чистый» процент — доля от накопленной левой части: `100 + 10%` = 110 |
| `*` `×` `/` `÷` | умножение/деление | `200 × 10%` = 20, `200 / 10%` = 2000 |
| `^` | степень | никогда НЕ XOR (XOR — слово `xor` в целочисленной дорожке) |
| `%` (постфикс) | `p%` = p/100 | семантический «процент» в аддитивном контексте |
| `x` (постфикс) | `1.5x` = множитель 1.5 | распознаётся только если нет активной переменной `x` |
| `of` (инфикс) | `15% of 490` = 0.15 × 490 | левая часть — процент, множитель или доля: `2/3 of 600` = 400 |
| `<` `<=` `>` `>=` | сравнения | числовые; результат — логический |
| `==` `!=` | равенство/неравенство | логический результат |
| `and` `&&` | конъюнкция | ленивая (ленивость: `false && (1/0 > 0)` истинно безопасно = false) |
| `or` `\\|\\|` | дизъюнкция | ленивая |
| `not` `!` | отрицание | префикс |
| `if a then b else c` | условие | нижний приоритет; ветки — полные выражения; `else` обязателен |

Логические значения — настоящий тип: `true`/`false` **никогда** не приводятся к
1/0 (смешение типов в одном операторе — ошибка).

### Целочисленная дорожка (точные Int64)

Строгу активируют: литералы `0x…`/`0b…`/`0o…`, вызовы `int(` `bin(` `oct(`
`hex(`, фразы `… as|in <база>` / `… to base N`, битовые глифы `&` `|` `<<` `>>`
и слово `xor` (глифы только при математическом содержимом строки — `fish &
chips` остаётся прозой). Слабую — слово `and`/`or` с «математическими»
соседями.

Приоритет дорожки, от низшего к высшему:
`if/then/else` → `||` → `&&` → `|`/`or` → `xor` → `&`/`and` → сравнения
`== != < <= > >=` → сдвиги `<< >>` → `+ -` → `* / %` → `^` → унарные →
первичные.

| Оператор | Смысл | Примечание |
|---|---|---|
| `&` | побитовое И | |
| `\\|` | побитовое ИЛИ | если оба операнда — логические, то ленивое логическое ИЛИ |
| `xor` | побитовое исключающее ИЛИ (слово) | `6 xor 3` = 5 |
| `<<` | сдвиг влево | ступень 0…63, переполнение — ошибка (checked) |
| `>>` | сдвиг вправо | ступень 0…63, арифметический для отрицательных |
| `/` | целое деление | результат выходит за решётку (переход в Double) при остатке |
| `%` | остаток | |
| `^` | степень | проверка ступени; отрицательная ступень → Double |

Все значения — точные Int64: `0x7FFFFFFFFFFFFFFF` = 9223372036854775807,
переполнение — видимая ошибка, никогда не «обёртка» и не Double.

## Встроенные функции (23)

Вызов: `имя(арг1, arg2, …)`, имя — строчные буквы (регистр не важен),
допускается пробел перед `(`. Вызов строгий: неизвестное имя, неверная
аргументность, пропущенная запятая, лишняя запятая, незакрытая скобка, выход за
область определения — детерминированная ошибка. В вызывной позиции встроенная
функция приоритетнее переменной того же имени (`sum = 5` не мешает `sum(1,2)`);
во всех прочих позициях `sum` — обычный идентификатор. Функции — скалярные
(без единиц), вложенные вызовы разрешены. Десятичная-запятая аргументы — НЕ
поддерживаются; аргументы разделяются `,` (запятая-разделитель) — при формате
с запятой в качестве десятичного разделителя для аргументов используйте `;`.

Запятая внутри вызова: `sum(1,234)` — одно число 1234 (запятая-группировка:
точно 3 цифры после и целая часть перед), `sum(1, 234)` — два аргумента,
`sum(1,2,3)` — три аргумента, `1,234,567` — одно число.

| Функция | Аргументы | Смысл | Область | Пример |
|---|---|---|---|---|
| `sqrt` | 1 | квадратный корень | x ≥ 0 | `sqrt(16)` → 4 |
| `abs` | 1 | модуль | любая | `abs(-3)` → 3 |
| `round` | 1–2 | округление (от нуля); 2-й аргумент — целые цифры −15…15 | d целое | `round(2.5)` → 3, `round(2.345, 2)` → 2.35 |
| `min` | ≥1 | минимум | — | `min(3, 1, 2)` → 1 |
| `max` | ≥1 | максимум | — | `max(1, 2)` → 2 |
| `sum` | ≥1 | сумма | — | `sum(1, 2, 3)` → 6 |
| `average` | ≥1 | среднее (устойчивое к переполнению) | — | `average(1, 2, 3)` → 2 |
| `pow` | 2 | степень (контракт `^`) | конечный результат | `pow(2, 10)` → 1024 |
| `ln` | 1 | натуральный логарифм | x > 0 | `ln(e)` → 1 |
| `log` | 1–2 | логарифм: 1 арг — по основанию 10; 2 арг — по основанию b | x > 0; b > 0, b ≠ 1 | `log(100)` → 2, `log(8, 2)` → 3 |
| `log10` | 1 | логарифм по основанию 10 | x > 0 | `log10(1000)` → 3 |
| `sin` | 1 | синус | **радианы** | `sin(0)` → 0 |
| `cos` | 1 | косинус | **радианы** | `cos(0)` → 1 |
| `tan` | 1 | тангенс | **радианы** | `tan(0)` → 0 |
| `asin` | 1 | арксинус | модуль x ≤ 1, радианы | `asin(1)` → π/2 |
| `acos` | 1 | арккосинус | модуль x ≤ 1, радианы | `acos(0)` → π/2 |
| `atan` | 1 | арктангенс | любые, радианы | `atan(1)` → π/4 |
| `radians` | 1 | градусы → радианы | — | `radians(180)` → π |
| `degrees` | 1 | радианы → градусы | — | `degrees(atan(1))` → 45 |
| `int` | 1 | целое (десятичная база) | точное целое, Int64 | `int(45)` → 45 |
| `bin` | 1 | целое в двоичной базе | точное целое, Int64 | `bin(5)` → `0b101` |
| `oct` | 1 | целое в восьмеричной базе | точное целое, Int64 | `oct(8)` → `0o10` |
| `hex` | 1 | целое в шестнадцатеричной базе | точное целое, Int64 | `hex(255)` → `0xFF` |
В точной (целочисленной) дорожке `int/bin/oct/hex` возвращают точный Int64 с
своей базой представления; на скалярной (Double) дорожке — строгое целое
значение.

## Системы счисления

Литералы строгой формы (регистр префикса не важен: `0X`, `0B`, `0O`):

| Префикс | База | Цифры |
|---|---|---|
| `0x` | 16 | `0-9 A-F` |
| `0b` | 2 | `0 1` |
| `0o` | 8 | `0-7` |

Правила:

- Подчёркивания только МЕЖДУ двумя цифрами: `0x1_0`, `100_000`; двойные, на
  краях и после префикса — ошибка (`0x_1F`, `0x1F_`).
- Зnak — знаково-модульный: `-0x10` = −16; `0x8000000000000000` = −9223372036854775808
  (Int64.min); переполнение (напр. `0x10000000000000000`) — ошибка.
- Каноническое отображение: `0b101`, `0o55`, `0xFF` — с префиксом; отрицательные
  с `-`.

База-имена (регистр не важен):

| Имя | База |
|---|---|
| `decimal`, `base10` | 10 |
| `binary`, `base2` | 2 |
| `octal`, `base8` | 8 |
| `hex`, `hexadecimal`, `base16` | 16 |
| `base 2` / `base 8` / `base 10` / `base 16` (разделённые пробелом, целое число) | 2 / 8 / 10 / 16 |

Шаблоны-фразы:

```text
<expr> as <база-имя>          255 as hex            → 0xFF
<expr> in <база-имя>          99 in binary          → 0b1100011
<expr> to base 8              64 to base 8          → 0o100
```

Примеры (все — проверенные тестами):

```text
0x1F + 1              → 0x20
0x1F in decimal       → 31
0b101101 + 1          → 0b101110
0o55 + 1              → 0o56
0x1_0                 → 0x10
100_000 as hex        → 0x186A0
256 as hex            → 0x100
16 in binary          → 0b10000
-0x10                 → -16
1 << 4                → 16
32 >> 2               → 8
0xFF & 0x0F           → 0x0F
5 | 2                 → 7
6 xor 3               → 5
5 << 3                → 40
(5 << 3) / 2          → 20
x = 0x1F
x & 1                 → 1
x + 1                 → 0x20
x as hex              → 0x20
```

Сдвиги `<<`/`>>` принимают ступень 0…63 (больше — ошибка); `>>` — арифметический
для отрицательных. `and`/`or`/`xor` — контекстные слова: для двух целых —
побитовые, для двух логических — логические (ленивые для `and`/`or`), смешение
типов в одном операторе — строгая ошибка. Деление с остатком, степень с
отрицательным показателем и нецелые значения «выходят» за решётку в Double.
На границах дорожек ставьте скобки явно.

## Проценты

Процентный литерал: `10%` = 0.1. В аддитивном контексте правый «чистый»
процент — доля от накопленной левой части: `100 + 10%` = 110, `110 − 5%` =
104.5; во всех остальных контекстах — обычный скаляр: `200 × 10%` = 20,
`200 / 10%` = 2000. Результат «процентного» вида отображается как `30%`, а не
`0.3`; множительный — как `1.5x`; дробный — как `1/2`.

Строгие фразовые шаблоны (ключевые слова: `of on off is what as a to percent
percentage fraction multiple multiplier x if`; регистр не важен; активная
переменная/константа с именем ключевого слова отключает все формы, его
использующие — `of = 5` убивает все `of`-формы на листе):

| Шаблон | Пример | Результат | Правило |
|---|---|---|---|
| `<p>% of <v>` | `15% of 490` | 73.5 | процент × значение (денежное значение правой части допустимо) |
| `<p>% on <v>` | `15% on 200` | 230 | v × (1 + p) |
| `<p>% off <v>` | `30% off 200` | 140 | v × (1 − p) |
| `<v> is <p>% of what` | `100 is 50% of what` | 200 | v ÷ p (обратный базис) |
| `<v> is <p>% off what` | `100 is 20% off what` | 125 | v ÷ (1 − p) |
| `<v> is <p>% on what` | `100 is 25% on what` | 80 | v ÷ (1 + p) |
| `<a> is what % of <b>` | `50 is what % of 200` | 25% | a ÷ b как процент |
| `<a> is what % off <b>` | `140 is what % off 200` | 30% | (b − a) ÷ b |
| `<a> is what % on <b>` | `230 is what % on 200` | 15% | (a − b) ÷ b |
| `<a> as a % of <b>` | `100 as a % of 800` | 12.5% | a ÷ b как процент |
| `<a> to <b> is what %` | `100 to 130 is what %` | 30% | (b − a) ÷ a |
| `<a> to <b> as %` | `100 to 130 as %` | 30% | (b − a) ÷ a |
| `<m>x of/on/off <v>` | `1.5x of 20`, `1.5x on 20`, `1.5x off 20` | 30 / 50 / −10 | множитель: `of` = v·m; `on` = v·(1+m); `off` = v·(1−m) — ровно как у процентов (100% off = 0) |
| `<a>/<b> %` (терминальный пробел+`%`) | `20/200 %` | 10% | превращает предшествующее деление в процент; `20/200%` (без пробела) — legacy-постфикс, 10 |
| `<p>% as fraction` | `50% as fraction` | 1/2 | сокращённая рациональная дробь |
| `<a>/<b> as fraction` | `2/10 as fraction` | 1/5 | |
| `<d> as %` | `0.25 as %` | 25% | десятичная → процент |
| `<a> as x of <b>` | `20 as x of 5` | 4x | отношение как множитель |
| `<a> to <b> as x` | `10 to 15 as x` | 1.5x | отношение как множитель |
| `20% is 500, what is 750` | | 17.5% | три значения: B × L ÷ A |
| `if 500 is 20%, what is 750` | | 30% | три значения: A × C ÷ B |

Операнды оценивает общее строгое ядро (именованные значения, маркеры валют,
имена денег). Формы, делящие деньги разных валют (`50 is what % of 200` при
разных валютах), — ошибка; дробление нуля — ошибка. Ничто здесь не приводит
булевы и валюты к числам. Нулевые базы и бесконечные значения — ошибка.

## Естественные деньги

Маркеры валюты (одна таблица, самая длинная побеждает: `CN¥` не съедается
хвостом `¥`):

`CA$ NZ$ HK$ MX$ NT$ A$ S$ R$ CN¥ Rp RM zł Kč $ € £ ¥ ₽ ₩ ₹ ₺ ₴ ₫ ₱ ฿ ₪ ₦ ₾ ₸ ₮ ₯ ៛ ₡ ₲ ₵`

Расположение: префикс (`$45`, `Rp25000`, `zł100`) или постфикс (`45$`,
`2.5K$`, `100zł`); удвоенные/некорректные маркеры — не маркеры; `km$5` — не
маркер. `Bare $` → USD, bare `¥` → JPY (Китай — однозначный `CN¥`). Альтернатива
маркерам — ISO-код-аннотация рядом с числом: `100 USD`.

Ввод сумм: группировка (`$3,400`), десятичные (`$2.50`), компактные суффиксы
(`$3k`). Одна валюта на строку: `$10 + €5` — скрытая ошибка. Имена валютных
значений: объявление `lunch = $45` (имя — 1–6 ASCII-слов или одно слово, ≤ 40
символов), затем ссылка `2 people × lunch`.

Процентные и арифметические операции внутри денег — те же общие операторы:
`+ − × ÷ of ( )`, контекстные проценты (`$100 + 10%` = 110$).

Временные ставки: `per <time>` и `/ <time>` открывают ставку
(`$24 per day`, `$85 / hr`); числовое время (`30 days`, `8 hrs`) — длительность,
и умножение её на ставку аннулирует размерность: `$24 per day × 12 hrs` =
12$. Коэффициенты времени — точные каталожные (секунды). Неаннулированная
ставка — скрытая ошибка, никогда не число. Точка-конец фразы принимается
(`8 hrs.`); десятичная точка не срезается.

Полный набор нейтральных слов (только они намеренно принимаются вокруг сумм;
любое другое слово делает строку некорректной — «неизвестные денежные фразы»
никогда не гадается):

`was is lunch dinner breakfast earnings income salary people person tip tips
tax taxes sales total bill order cost price item items each spent paid got
for the food material materials`

Полный набор временных слов (ставит ставку/длительность, точные каталожные
коэффициенты):

`s sec secs second seconds min mins minute minutes h hr hrs hour hours d day
days w wk wks week weeks`

Примеры (проверенные):

```text
lunch was $45 + $60     → 105$
tip for 2 people 18%     → 18%
$24 per day × 12 hrs     → 12$
$85 / hr × 2 hrs         → 170$
2 people × lunch         → 90$   (после lunch = $45)
sales tax 8% of $120     → 9.6$
```

## Команда `total`

Точная команда: строка, целиком равная `total` (регистр не важен). Она
оценивает сумму **eligible** результатов текущей секции (включая строку с
командой) и выдаёт её ответом; строки `total` друг друга не пересчитывают
(ранее вычисленный total в состав следующей суммы не входит, а обычная
ссылка на строку-сумму — обычная строка и входит).

Eligible (входят в сумму): конечные скалярные числа — включая процентный и
множительный виды, именованные скаляры, точные целые (Их проекция в Double
точна при |v| ≤ 2^53). Не входят: деньги, количества с единицами, логические,
даты, ошибки, строки-пробелы.

Затенение: активное именованное значение/константа с именем `total` отключает
команду (строка становится обычным именованным значением). Команда `total` —
это встроенная строка-сумма секции; она отличается от нижней панели Total
в окне приложения (она суммирует весь лист независимо от секций).

## Даты

Строгий ограниченный синтаксис (английские слова, регистр не важен):

```text
<date> [ <sign> <целое> <duration> ]
<date>     := today | tomorrow | yesterday
             | <месяц> <день>
             | <месяц> <день>, <год>
             | <день> <месяц> [<год>]
<duration> := day(s) | week(s) | month(s) | year(s)
```

Слова длительности (все принимаемые формы): `day days`, `week weeks`, `month months`,
`year years`. Знак — `+` или `−` (также `-`).

Месяцы (сокращённые и полные, регистр не важен):

| # | Сокращённые | Полное |
|---|---|---|
| 1 | jan | january |
| 2 | feb | february |
| 3 | mar | march |
| 4 | apr | april |
| 5 | may | may |
| 6 | jun | june |
| 7 | jul | july |
| 8 | aug | august |
| 9 | sep, sept | september |
| 10 | oct | october |
| 11 | nov | november |
| 12 | dec | december |

Семантика: грегорианский календарь, компонентная арифметика `Calendar`
(НЕТ множителей 86400 секунд), привязка к локальному полудню, чтобы DST не
сдвигал день. Год результата показывается, если он задан во вводе или
результат выходит за год ввода.

Ограничения и ошибки:

- Периоды до 1 000 000; больше — скрытая ошибка.
- `Feb 30` — дата-визуально, но не валидная — скрытая ошибка.
- `May 5 + 43` (без слова duration) — ошибка, никогда не «сброшенная в
  числа».
- `May 5 + 43 days extra` — хвост после валидной даты — ошибка.
- Одиночное слово-месяц без дня (`may`) — не дата (обычная проза).

Примеры (проверенные):

```text
today                 → сегодня (по локальному календарю)
tomorrow + 1 month
yesterday - 2 weeks
May 5                 → 5 мая (текущего года)
May 5, 2026 + 30 days
5 May 2026
dec 31
```

## Единицы

Форма количества: `<число> <единица>` — пробел обязателен; склеенная буква —
компактная запись (`5m` = 5 000 000, не метры). Единица — атом из каталога
(с его алиасами и SI-префиксами) или выражение над единицами.

### Выражения над единицами

Допустимы операторы `*` `·` `/` и степенные `^`, `²`, `³` (база — буква,
например `m²`, `m³`): `km/h`, `kg/m³`, `N·m`, `m/s²`. Ограничения:

- Компоновка только «линейная»: ступени не могут образовывать новые
  размерности произвольно — составные формы ограничены `^2`, `^3` и
  дробями/произведениями атомов.
- Температуры, валюты и топливные единицы — **специальные**: участвуют только
  standalone, в составные выражения не входят (`C°/h` — ошибка).
- Конвертация `to|in|as <unit>`: правая часть — целевая единица; левая —
  количество. Измерения (dimension signatures) должны совпадать: `10 km in m`
  = 10 000 m; `10 km in kg` — ошибка.
- Температуры: абсолютные шкалы (`C°` `F°` `K°` `R°`) конвертируются по
  аффинным формулам, не по коэффициенту: `100 C° to F°` = 212 F°.
- Топливные: `L/100km`, `L/km` и обратные (км/л-вид) — семейство fuel.

### Чувствительность к регистру

Алиасы сохраняют регистр: `MB` (мегабайты) и `Mb` (мегабиты) — разные
единицы. `mb` — ни то ни другое (двусмысленно после case-fold) — неизвестная
единица, детерминированно. Метка (label) единицы принимается как алиас
ввода: `10 meters` = `10 m`.

### SI-префиксы

Допустимые атомы: `p n µ m c d k K M G T P` (10⁻¹⁵…10¹⁵). Каждый атом
каталога объявляет свои; в приложении перечислены явно. `µ` — греческая
мю (U+00B5 или U+03BC), не латинская `u`.

Сгенерированные (не перечисляемые) формы: множественные числа атомов
(`meters` = `meter`) и prefixed-формы (`km`, `mm`, `kWh` …) — правило:
префикс из списка атома + атом.

### Арифметика количеств (R84)

Строгий язык: количества, простые числа, именованные значения, операторы
`+ - * / ^ × ÷ of ( )`, суффикс `to|in|as <unit>`. Строка либо целиком в этом
языке (shape hit — ошибка видимая), либо вообще нет (падает в деньги/даты/прозу).

| Операция | Правило | Пример |
|---|---|---|
| `+` `−` | одинаковая размерность; «простая» сторона принимает единицу другой | `300 + 20 km` = 320 km; `1 km + 500 m` = 1.5 km |
| `×` `/` | композиция размерностей; валюты/температуры отвергаются | `90 km / 3 day` = 30 km/day |
| `^` | степень (ограничения составных форм) | `10 m × 2 m` = 20 m² |
| Отображение | результат в **более грубом** операнд-единице (большой базовый коэффициент); равенство — левый | `1 km + 500 m` → км |

Именованные количества и токены: `distance = 10 km`, затем `distance in m`.
Встроенные ограничения: температуры/валюты/топливо — не участвуют в составных
выражениях.

### Строгие фразовые шаблоны (R84)

| Шаблон | Пример | Смысл |
|---|---|---|
| `<qtyA> in <qtyB>` | `10 km in 45 min` | скорость/pace/rate: A ÷ B → `0.2222 km/min` |
| | `45 min in 10 km` | pace → `4.5 min/km` |
| | `1 Gbit in 5 s` | transfer rate → `0.2 Gbit/s` |
| `<qty> at <money> per <unit>` | `2.5 kg at €3 per kg` | цена: qty/unit × цена → `€7.50` |
| `per <unit>` (внутри алгебры) | `90 km per 3 day` | 30 km/day (оператор mixed-stage) |
| PPI (в обе стороны) | `10 in in px at 96 ppi` | 960 px; `960 px at 96 ppi to in` = 10 in (1 in = 0.0254 m exactly) |
| Кулинарные плотности | `200 g of flour to ml` | масса → объём через таблицу `CookingDensities` (≈) |
| | `1 cup of honey to g` | объём → масса (≈) |
| | `1 L of oil as kg` | цели противоположного вида (`in` / `as` / `to`) |

Все фразовые дорожки **владеют** совпавшей строкой: ошибка — видимая, никогда
не «word-strip fallback».

### Таблица кулинарных плотностей (21 позиция, версия `r84-1`)

Приблизительные плотности упаковки (воспроизводят стандартные US-baking cup
таблицы; значения закреплены строкой `version`, будущая перекалибровка —
видимое изменение, никогда не «тихое дрейф»). Ввод: нижний регистр, пробелы и
дефисы игнорируются (`brown sugar` = `brown-sugar` = `brownsugar`).

| Имя ввода | Метка | кг/м³ | Примечание |
|---|---|---|---|
| water | water | 1000 | 1 cup ≈ 237 g |
| flour | all-purpose flour | 528.3 | 1 cup ≈ 125 g (spooned, leveled) |
| sugar | granulated sugar | 845.4 | 1 cup ≈ 200 g |
| brownsugar | brown sugar (packed) | 930.3 | 1 cup ≈ 220 g |
| icingsugar | powdered sugar | 507.2 | 1 cup ≈ 120 g |
| salt | table salt | 1153.9 | 1 cup ≈ 273 g |
| butter | butter | 959.4 | 1 cup ≈ 227 g |
| honey | honey | 1437.1 | 1 cup ≈ 340 g |
| milk | whole milk | 1031.3 | 1 cup ≈ 244 g |
| oil | vegetable oil | 921.4 | 1 cup ≈ 218 g |
| rice | white rice (dry) | 782.0 | 1 cup ≈ 185 g uncooked |
| cornstarch | cornstarch | 541.0 | 1 cup ≈ 128 g |
| oats | rolled oats (dry) | 338.2 | 1 cup ≈ 80 g |
| cocoa | cocoa powder (sifted) | 359.3 | 1 cup ≈ 85 g |
| chocolate | chocolate chips | 718.5 | 1 cup ≈ 170 g |
| peanutbutter | peanut butter | 1090.5 | 1 cup ≈ 258 g |
| creamcheese | cream cheese | 976.4 | 1 cup ≈ 231 g |
| yogurt | plain yogurt | 1035.6 | 1 cup ≈ 245 g |
| applesauce | applesauce | 1031.3 | 1 cup ≈ 244 g |
| cornmeal | cornmeal | 613.1 | 1 cup ≈ 145 g |
| yeast | dry yeast | 450 | 1 cup ≈ 107 g (very light) |

### Пользовательские единицы (настройка)

Грамматика (Settings → Units):

- Имя: 1–6 ASCII-слов, ≤ 40 символов, первое слово — с буквы; уникально
  (коллизия с каталогом или другим кастомным — отклоняется).
- Определения: либо `<число> <existing unit expression>` (например `2.54 cm`),
  либо точное новое имя единицы (для атомов).
- Зависимости разрешаются в порядке объявления и вне его (순环 — ошибка);
  глобальный лимит — 100 пользовательских единиц.
- Кастомные единицы **app-global** (настройки приложения), не сохраняются в
  `.nlx`-листе.
- Множественное число имени принимается автоматически (правило атомов).

Проверенные примеры (R84):

```text
10 km to m                → 10 000 m
300 + 20 km               → 320 km
90 km / 3 day             → 30 km/day
10 km in 45 min           → 0.2222 km/min
45 min in 10 km           → 4.5 min/km
1 Gbit in 5 s             → 0.2 Gbit/s
2.5 kg at €3 per kg       → €7.50
90 km per 3 day           → 30 km/day
10 in in px at 96 ppi     → 960 px
200 g of flour to ml      → 378.6 ml (≈)
1 cup of honey to g       → 340 g (≈)
```
## Приложение: полный каталог невалютных единиц

403 записей `UnitCatalog` (атомные единицы; валюты — отдельный каталог, см. раздел «Валюты»).
| id | метка | явные алиасы | SI-префиксы | размерность |
|---|---|---|---|---|
| `meter` | m | m · meter · meters · metre · metres | p,n,µ,m,c,d,k,K,M,G,T | L |
| `kilometer` | km | km · kilometer · kilometers | — | L |
| `inch` | in | in · inch · inches · in. | — | L |
| `foot` | ft | ft · foot · feet | — | L |
| `yard` | yd | yd · yard · yards | — | L |
| `mile` | mi | mi · mile · miles | — | L |
| `nautical-mile` | nmi | nmi · nautical mile · international nautical mile | — | L |
| `mil` | mil | mil · mils · thou · thous | — | L |
| `astronomical-unit` | AU | AU · au · astronomical unit | — | L |
| `light-year` | ly | ly · light year · light-year | — | L |
| `parsec` | pc | pc · parsec · parsecs | — | L |
| `angstrom` | Å | Å · angstrom · angstroms | — | L |
| `micron` | µm | µm · micron · microns | — | L |
| `hand` | hand | hand · hands | — | L |
| `us-survey-foot` | US ft | US ft · us survey foot · survey foot | — | L |
| `fathom` | fathom | fathom · fathoms | — | L |
| `rod` | rod | rod · rods · pole · poles | — | L |
| `chain` | chain | chain · chains | — | L |
| `furlong` | furlong | furlong · furlongs · fur | — | L |
| `pixel` | px | px · pixel · pixels | — | — |
| `density-kg-m3` | kg/m³ | kg/m³ · kg/m3 · kilogram per cubic meter | — | L3·M·T |
| `density-g-l` | g/L | g/L · g/l · gram per liter | — | L3·M·T |
| `density-g-cm3` | g/cm³ | g/cm³ · g/cm3 · g/mL · g/ml · gram per milliliter | — | L3·M·T |
| `density-lb-ft3` | lb/ft³ | lb/ft³ · lb/ft3 · pound per cubic foot | — | L3·M·T |
| `type-point` | pt (type) | pt (type) · typographic point · type point | — | L |
| `pica` | pica | pica · picas · type pica | — | L |
| `sq-meter` | m² | m² · m2 · square meter · square metre · sq m · sqm | m,c,k,K,M | L2 |
| `hectare` | ha | ha · hectare · hectares | — | L2 |
| `acre` | acre | acre · acres | — | L2 |
| `sq-foot` | ft² | ft² · ft2 · square foot · square feet · sq ft · sqft | — | L2 |
| `sq-inch` | in² | in² · in2 · square inch · sq in | — | L2 |
| `sq-yard` | yd² | yd² · yd2 · square yard | — | L2 |
| `sq-mile` | mi² | mi² · mi2 · square mile | — | L2 |
| `are` | are | are | — | L2 |
| `rood` | rood | rood · roods | — | L2 |
| `barn` | barn | barn · barns | — | L2 |
| `section` | section | section · sections | — | L2 |
| `liter` | L | L · l · liter · litre · liters · litres | µ,c,d,k,K | L3 |
| `milliliter` | ml | ml · mL · milliliter · milliliters | — | L3 |
| `cubic-meter` | m³ | m³ · m3 · cubic meter · cubic metre | k,K,M | L3 |
| `cubic-inch` | in³ | in³ · in3 · cubic inch | — | L3 |
| `cubic-foot` | ft³ | ft³ · ft3 · cubic foot · cubic feet | — | L3 |
| `cubic-yard` | yd³ | yd³ · yd3 · cubic yard | — | L3 |
| `us-teaspoon` | tsp | tsp · teaspoon · teaspoons · us teaspoon | — | L3 |
| `metric-teaspoon` | metric tsp | metric teaspoon · metric tsp | — | L3 |
| `us-tablespoon` | tbsp | tbsp · tablespoon · tablespoons · us tablespoon | — | L3 |
| `us-fluid-ounce` | fl oz | fl oz · us fl oz · us fluid ounce · fluid ounce | — | L3 |
| `us-cup` | cup | cup · cups · us cup | — | L3 |
| `us-pint` | pt | pt · pint · pints · us pint | — | L3 |
| `us-quart` | qt | qt · quart · quarts · us quart | — | L3 |
| `us-gallon` | gal | gal · gallon · gallons · us gallon | — | L3 |
| `uk-fluid-ounce` | uk fl oz | uk fl oz · imperial fluid ounce · uk fluid ounce | — | L3 |
| `uk-pint` | uk pt | uk pt · imperial pint · uk pint | — | L3 |
| `uk-quart` | uk qt | uk qt · imperial quart · uk quart | — | L3 |
| `uk-gallon` | uk gal | uk gal · uk_gal · imperial gallon · imperial gallons · uk gallon | — | L3 |
| `metric-cup` | metric cup | metric cup · metric cups | — | L3 |
| `metric-tablespoon` | metric tbsp | metric tablespoon · metric tablespoons | — | L3 |
| `imperial-tablespoon` | imp tbsp | imperial tablespoon · imperial tablespoons · uk tablespoon | — | L3 |
| `dessertspoon` | dessertspoon | dessertspoon · dessertspoons · dsp | — | L3 |
| `us-fluid-dram` | US fl dr | us fluid dram · fluid dram | — | L3 |
| `us-oil-barrel` | bbl | bbl · barrel · barrels · us oil barrel · oil barrel · petroleum barrel | — | L3 |
| `us-bushel` | bushel | bushel · bushels · us bushel | — | L3 |
| `us-peck` | peck | peck · pecks · us peck | — | L3 |
| `gram` | g | g · gram · grams | p,n,µ,m,c,d,k,K | M |
| `kilogram` | kg | kg · kilogram · kilograms | — | M |
| `tonne` | t | t · tonne · tonnes · metric ton · ton | — | M |
| `grain` | grain | grain · grains · gr | — | M |
| `carat` | ct | ct · carat · carats · karat | — | M |
| `ounce` | oz | oz · ounce · ounces · avoirdupois ounce | — | M |
| `pound` | lb | lb · pound · pounds · pound avoirdupois | — | M |
| `stone` | st | st · stone · stones | — | M |
| `short-ton` | short ton | short ton · us ton · short tons · shortton | — | M |
| `long-ton` | long ton | long ton · uk ton · long tons · longton · british ton | — | M |
| `dalton` | Da | Da · dalton · daltons · amu · atomic mass unit · unified atomic mass unit | — | M |
| `slug` | slug | slug · slugs | — | M |
| `quintal` | quintal | quintal · quintals | — | M |
| `us-hundredweight` | cwt (US) | us hundredweight · us cwt · short hundredweight | — | M |
| `uk-hundredweight` | cwt (UK) | uk hundredweight · uk cwt · long hundredweight · imperial hundredweight | — | M |
| `troy-ounce` | oz t | oz t · ozt · troy ounce · troy ounces | — | M |
| `pennyweight` | dwt | dwt · pennyweight · pennyweights | — | M |
| `celsius` | C° | c · C · °c · celsius · c° | — | special |
| `fahrenheit` | F° | f · F · °f · fahrenheit · f° | — | special |
| `kelvin` | K° | k · K · °k · kelvin · k° | — | special |
| `rankine` | R° | r · R · °r · rankine · r° | — | special |
| `second` | s | s · second · seconds · sec · secs | n,µ,m | T |
| `millisecond` | ms | ms · millisecond · milliseconds | — | T |
| `minute` | min | min · minute · minutes | — | T |
| `hour` | h | h · hour · hours · hr · hrs | — | T |
| `day` | day | day · days | — | T |
| `week` | week | week · weeks · wk | — | T |
| `fortnight` | fortnight | fortnight · fortnights · fn | — | T |
| `julian-year` | jyear | jyear · julian year · jy | — | T |
| `gregorian-year` | yr | yr · year · years · gregorian year · average year · average gregorian year | — | T |
| `average-month` | mo | mo · month · months · average month · average gregorian month | — | T |
| `common-year` | common year | common year · common year (365 days) | — | T |
| `average-quarter` | quarter (time) | quarter (time) · average quarter | — | T |
| `m-per-s` | m/s | m/s · meters per second | k,K,M | L·T |
| `km-per-h` | km/h | km/h · kph · kmh · kilometers per hour · kilometres per hour | — | L·T |
| `mph` | mph | mph · miles per hour · mi/h | — | L·T |
| `ft-per-s` | ft/s | ft/s · feet per second | — | L·T |
| `knot` | kn | kn · knot · knots | — | L·T |
| `speed-of-light` | c₀ | c₀ · c0 · speed of light | — | L·T |
| `mach` | Mach | Mach · standard mach · mach number | — | L·T |
| `m-per-s2` | m/s² | m/s² · m/s2 · meters per second squared | k,K | L2·T |
| `ft-per-s2` | ft/s² | ft/s² · ft/s2 · feet per second squared | — | L2·T |
| `standard-gravity` | g₀ | standard gravity · g0 · gn · gravity · g-force · gforce | — | L2·T |
| `km-per-h-s` | km/h/s | km/h/s · kph/s · kilometers per hour per second | — | L2·T |
| `radian` | rad | rad · radian · radians | — | — |
| `degree` | deg | deg · degree · degrees · ° | — | — |
| `gradian` | grad | grad · gradian · grads · gon | — | — |
| `turn` | turn | turn · turns · revolution · revolutions · rev · cycle · cycles | — | — |
| `arcmin` | arcmin | arcmin · arc minute · arcminutes · minute of arc · ′ | — | — |
| `arcsec` | arcsec | arcsec · arc second · arcseconds · second of arc · ″ | — | — |
| `pascal` | Pa | Pa · pascal · pascals | µ,m,c,k,K,M,G | L·M·T |
| `hectopascal` | hPa | hPa · hectopascal · hectopascals | — | L·M·T |
| `bar` | bar | bar · bars | m | L·M·T |
| `atmosphere` | atm | atm · atmosphere · atmospheres · standard atmosphere | — | L·M·T |
| `torr` | torr | torr · torrs · mmhg · mm hg | — | L·M·T |
| `psi` | psi | psi · lbf/in² · pounds per square inch · pound per square inch | — | L·M·T |
| `ksi` | ksi | ksi · kip per square inch | — | L·M·T |
| `inhg` | inHg | inHg · in hg · inches of mercury | — | L·M·T |
| `techn-atm` | at | at · technical atmosphere · techn atm | — | L·M·T |
| `kgf-per-cm2` | kgf/cm² | kgf/cm² · kgf/cm2 · kilogram force per square centimeter | — | L·M·T |
| `mm-h2o` | mmH2O | mmH2O · mm h2o · millimeter of water | — | L·M·T |
| `cm-h2o` | cmH2O | cmH2O · cm h2o · centimeter of water | — | L·M·T |
| `psf` | psf | psf · pound per square foot | — | L·M·T |
| `newton` | N | N · newton · newtons | µ,m,c,k,K,M,G | L·M·T |
| `dyne` | dyne | dyne · dynes | — | L·M·T |
| `lbf` | lbf | lbf · pound force · pound-force · lb force | — | L·M·T |
| `kgf` | kgf | kgf · kilogram force · kilogram-force · kp | — | L·M·T |
| `ounce-force` | ozf | ozf · ounce force · ounce-force | — | L·M·T |
| `kip` | kip | kip · kips · kilopound | — | L·M·T |
| `poundal` | poundal | poundal · poundals · pdl | — | L·M·T |
| `us-ton-force` | tonf (US) | us ton force · us ton-force · short ton force | — | L·M·T |
| `tonne-force` | tonf (t) | tonne force · tonne-force · tf · metric ton force | — | L·M·T |
| `newton-meter` | N·m | N·m · N m · N*m | — | L2·M·T |
| `lbf-foot` | lbf·ft | lbf·ft · lbf ft · lb-ft | — | L2·M·T |
| `lbf-inch` | lbf·in | lbf·in · lbf in · lb-in | — | L2·M·T |
| `kgf-meter` | kgf·m | kgf·m · kgf m · kgf*m | — | L2·M·T |
| `newton-centimeter` | N·cm | N·cm · N cm · N*cm · newton centimeter | — | L2·M·T |
| `newton-millimeter` | N·mm | N·mm · N mm · N*mm · newton millimeter | — | L2·M·T |
| `ozf-inch` | ozf·in | ozf·in · ozf in · oz-in · ounce force inch | — | L2·M·T |
| `joule` | J | J · joule · joules | m,µ,k,K,M,G,T | L2·M·T |
| `watt-hour` | Wh | Wh · watt hour · watt-hour · watt hours | — | L2·M·T |
| `kilowatt-hour` | kWh | kWh · kilowatt hour · kilowatt-hour | — | L2·M·T |
| `megawatt-hour` | MWh | MWh · megawatt hour | — | L2·M·T |
| `gigawatt-hour` | GWh | GWh · gigawatt hour | — | L2·M·T |
| `calorie` | cal | cal · calorie · calories | k,K | L2·M·T |
| `kilocalorie` | kcal | kcal · kilocalorie · kilocalories · Calorie · Calories · big calorie | — | L2·M·T |
| `btu` | BTU | BTU · btu · BTUs · british thermal unit | — | L2·M·T |
| `therm` | therm | therm · therms · us therm | — | L2·M·T |
| `ft-lbf` | ft·lbf | ft·lbf · ft lbf · foot pound force · foot-pound force · ftlbf | — | L2·M·T |
| `electronvolt` | eV | eV · electronvolt · electron volt | M,G,T | L2·M·T |
| `erg` | erg | erg · ergs | — | L2·M·T |
| `ton-tnt` | t TNT | t TNT · ton TNT · tonne TNT · ton of TNT | — | L2·M·T |
| `quad` | quad | quad · quads · quadrillion BTU | — | L2·M·T |
| `horsepower-hour` | hph | hph · horsepower hour · mechanical horsepower hour | — | L2·M·T |
| `tonne-oil-equivalent` | toe | toe · tonne of oil equivalent · ton oil equivalent | — | L2·M·T |
| `watt` | W | W · watt · watts | m,µ,k,K,M,G,T | L2·M·T |
| `horsepower` | hp | hp · horsepower · horse power · mechanical horsepower · imperial horsepower | — | L2·M·T |
| `metric-horsepower` | metric hp | metric hp · metric horsepower · cv · ps · pferd | — | L2·M·T |
| `btu-per-h` | BTU/h | BTU/h · btu/h · btuh · btu per hour | — | L2·M·T |
| `electric-horsepower` | hp (electric) | electric horsepower · electric hp · US horsepower | — | L2·M·T |
| `boiler-horsepower` | hp (boiler) | boiler horsepower · boiler hp | — | L2·M·T |
| `ton-refrigeration` | TR | TR · ton refrigeration · ton of refrigeration | — | L2·M·T |
| `hertz` | Hz | Hz · hertz | k,K,M,G | T |
| `rpm` | rpm | rpm · r/min · revolutions per minute · rev per minute | — | T |
| `bpm` | bpm | bpm · beats per minute | — | T |
| `bit` | bit | bit · bits · b | k,K,M,G,T,P | — |
| `byte` | B | B · byte · bytes | k,K,M,G,T,P | — |
| `kibibyte` | KiB | KiB · kibibyte · kibibytes | — | — |
| `mebibyte` | MiB | MiB · mebibyte · mebibytes | — | — |
| `gibibyte` | GiB | GiB · gibibyte · gibibytes | — | — |
| `tebibyte` | TiB | TiB · tebibyte · tebibytes | — | — |
| `pebibyte` | PiB | PiB · pebibyte · pebibytes | — | — |
| `kibibit` | Kib | Kib · kibibit · kibibits | — | — |
| `mebibit` | Mib | Mib · mebibit · mebibits | — | — |
| `gibibit` | Gib | Gib · gibibit · gibibits | — | — |
| `tebibit` | Tib | Tib · tebibit · tebibits | — | — |
| `pebibit` | Pib | Pib · pebibit · pebibits | — | — |
| `bit-per-s` | bit/s | bit/s · bps · bits per second · b/s | k,K,M,G,T | T |
| `byte-per-s` | B/s | B/s · bytes per second · BPS | k,K,M,G,T | T |
| `liter-per-s` | L/s | L/s · liters per second · litres per second | m,k,K | L3·T |
| `liter-per-min` | L/min | L/min · liters per minute | — | L3·T |
| `liter-per-h` | L/h | L/h · liters per hour | — | L3·T |
| `m3-per-s` | m³/s | m³/s · m3/s · cubic meters per second | — | L3·T |
| `m3-per-h` | m³/h | m³/h · m3/h · cubic meters per hour | — | L3·T |
| `gpm` | gpm | gpm · us gpm · us gallons per minute | — | L3·T |
| `cfs` | cfs | cfs · cubic feet per second | — | L3·T |
| `uk-gpm` | UK gpm | uk gpm · imperial gpm · imperial gallons per minute | — | L3·T |
| `cfm` | cfm | cfm · cubic feet per minute · ft³/min | — | L3·T |
| `us-mgd` | US mgd | us mgd · million gallons per day | — | L3·T |
| `bbl-per-d` | bbl/d | bbl/d · barrels per day · oil barrel per day | — | L3·T |
| `l100km` | L/100km | l/100km · L per 100 km · l per 100km · liters per 100 km · litres per 100 km | — | special |
| `lkm` | L/km | l/km · L per km · l per km · liters per km · litres per km | — | special |
| `kml` | km/L | km/l · km per liter · km per litre · kmpl | — | special |
| `mpg-us` | US mpg | mpg · us mpg · mpg (us) · us_mpg · mpg_us · usmpg | — | special |
| `mpg-uk` | UK mpg | uk mpg · mpg (uk) · uk_mpg · mpg_uk · ukmpg · imperial mpg · miles per imperial gallon | — | special |
| `miles-per-liter` | mi/L | mi/l · miles per liter · miles per litre | — | special |
| `us-gal100mi` | US gal/100mi | us gal/100mi · us gallons per 100 miles | — | special |
| `uk-gal100mi` | UK gal/100mi | uk gal/100mi · uk gallons per 100 miles | — | special |
| `pascal-second` | Pa·s | Pa·s · Pa s · Pa*s · pascal second | — | L·M·T |
| `poise` | P | P · poise · poises | — | L·M·T |
| `centipoise` | cP | cP · centipoise · centipoises | — | L·M·T |
| `reyn` | reyn | reyn · reyns | — | L·M·T |
| `m2-per-s` | m²/s | m²/s · m2/s · square meters per second | — | L2·T |
| `stokes` | St | St · stokes · stoke | — | L2·T |
| `centistokes` | cSt | cSt · centistokes | — | L2·T |
| `ft2-per-s` | ft²/s | ft²/s · ft2/s · square feet per second | — | L2·T |
| `ampere` | A | A · ampere · amperes · amp · amps | n,µ,m,k,K | A |
| `volt` | V | V · volt · volts | µ,m,k,K,M | L2·M·T·A |
| `ohm` | Ω | Ω · ohm · ohms | k,K,M,G | L2·M·T·A |
| `coulomb` | C | coulomb · coulombs | m,k,K | T·A |
| `amp-hour` | Ah | Ah · amp hour · ampere hour · amphour | — | T·A |
| `millicoulomb` | mC | mC · millicoulomb | — | T·A |
| `kilocoulomb` | kC | kC · kilocoulomb | — | T·A |
| `mah` | mAh | mAh · milliamp hour · milliampere hour | — | T·A |
| `farad` | F | farad · farads | — | L·M·T4·A2 |
| `picofarad` | pF | pF · picofarad · picofarads | — | L·M·T4·A2 |
| `nanofarad` | nF | nF · nanofarad · nanofarads | — | L·M·T4·A2 |
| `microfarad` | µF | µF · microfarad · microfarads | — | L·M·T4·A2 |
| `millifarad` | mF | mF · millifarad · millifarads | — | L·M·T4·A2 |
| `henry` | H | H · henry · henries | m,µ | L2·M·T·A |
| `siemens` | S | S · siemens · siemen · mho | m,µ | L·M·T3·A2 |
| `weber` | Wb | Wb · weber · webers | m | L2·M·T·A |
| `tesla` | T | T · tesla · teslas | m,µ | M·T·A |
| `gauss` | G | G · gauss | — | M·T·A |
| `candela` | cd | cd · candela · candelas | — | I |
| `lumen` | lm | lm · lumen · lumens | k,K,M | I |
| `lux` | lx | lx · lux | — | L·I |
| `footcandle` | fc | fc · foot-candle · foot candle · footcandle · footcandles | — | L·I |
| `becquerel` | Bq | Bq · becquerel · becquerels | m,k,K,M,G | T |
| `curie` | Ci | Ci · curie · curies | — | T |
| `gray` | Gy | Gy · gray · grays | m,µ,k,K,M | L2·M·T |
| `rad-dose` | rad (dose) | rads · radiation absorbed dose · rad dose · absorbed rad | — | L2·M·T |
| `sievert` | Sv | Sv · sievert · sieverts | m,k,K,M | L2·M·T |
| `rem` | rem | rem · rems | — | L2·M·T |
| `cur-AED` | AED | AED · UAE dirham · UAE dirhams · dirham · dirhams | — | special |
| `cur-AFN` | AFN | AFN | — | special |
| `cur-ALL` | ALL | ALL | — | special |
| `cur-AMD` | AMD | AMD | — | special |
| `cur-ANG` | ANG | ANG | — | special |
| `cur-AOA` | AOA | AOA | — | special |
| `cur-ARS` | ARS | ARS · Argentine peso · Argentine pesos | — | special |
| `cur-AUD` | AUD | AUD · Australian dollar · Australian dollars | — | special |
| `cur-AWG` | AWG | AWG | — | special |
| `cur-AZN` | AZN | AZN | — | special |
| `cur-BAM` | BAM | BAM | — | special |
| `cur-BBD` | BBD | BBD | — | special |
| `cur-BDT` | BDT | BDT · Bangladeshi taka · taka | — | special |
| `cur-BGN` | BGN | BGN · Bulgarian lev · lev | — | special |
| `cur-BHD` | BHD | BHD · Bahraini dinar · Bahraini dinars | — | special |
| `cur-BIF` | BIF | BIF | — | special |
| `cur-BMD` | BMD | BMD | — | special |
| `cur-BND` | BND | BND | — | special |
| `cur-BOB` | BOB | BOB | — | special |
| `cur-BRL` | BRL | BRL · Brazilian real · Brazilian reais · reais | — | special |
| `cur-BSD` | BSD | BSD | — | special |
| `cur-BTN` | BTN | BTN | — | special |
| `cur-BWP` | BWP | BWP | — | special |
| `cur-BYN` | BYN | BYN | — | special |
| `cur-BZD` | BZD | BZD | — | special |
| `cur-CAD` | CAD | CAD · Canadian dollar · Canadian dollars | — | special |
| `cur-CDF` | CDF | CDF | — | special |
| `cur-CHF` | CHF | CHF · Swiss franc · Swiss francs | — | special |
| `cur-CLF` | CLF | CLF | — | special |
| `cur-CLP` | CLP | CLP · Chilean peso · Chilean pesos | — | special |
| `cur-CNH` | CNH | CNH | — | special |
| `cur-CNY` | CNY | CNY · Chinese yuan · yuan · renminbi · RMB | — | special |
| `cur-COP` | COP | COP · Colombian peso · Colombian pesos | — | special |
| `cur-CRC` | CRC | CRC | — | special |
| `cur-CUP` | CUP | CUP | — | special |
| `cur-CVE` | CVE | CVE | — | special |
| `cur-CZK` | CZK | CZK · Czech koruna · koruna | — | special |
| `cur-DJF` | DJF | DJF | — | special |
| `cur-DKK` | DKK | DKK | — | special |
| `cur-DOP` | DOP | DOP | — | special |
| `cur-DZD` | DZD | DZD | — | special |
| `cur-EGP` | EGP | EGP · Egyptian pound · Egyptian pounds | — | special |
| `cur-ERN` | ERN | ERN | — | special |
| `cur-ETB` | ETB | ETB | — | special |
| `cur-EUR` | EUR | EUR · euro · euros · european euro · european euros | — | special |
| `cur-FJD` | FJD | FJD | — | special |
| `cur-FKP` | FKP | FKP | — | special |
| `cur-FOK` | FOK | FOK | — | special |
| `cur-GBP` | GBP | GBP · British pound · British pounds · pound sterling · sterling | — | special |
| `cur-GEL` | GEL | GEL · Georgian lari · lari | — | special |
| `cur-GGP` | GGP | GGP | — | special |
| `cur-GHS` | GHS | GHS · Ghanaian cedi · cedi | — | special |
| `cur-GIP` | GIP | GIP | — | special |
| `cur-GMD` | GMD | GMD | — | special |
| `cur-GNF` | GNF | GNF | — | special |
| `cur-GTQ` | GTQ | GTQ | — | special |
| `cur-GYD` | GYD | GYD | — | special |
| `cur-HKD` | HKD | HKD · Hong Kong dollar · Hong Kong dollars | — | special |
| `cur-HNL` | HNL | HNL | — | special |
| `cur-HRK` | HRK | HRK | — | special |
| `cur-HTG` | HTG | HTG | — | special |
| `cur-HUF` | HUF | HUF · Hungarian forint · forint | — | special |
| `cur-IDR` | IDR | IDR · Indonesian rupiah · rupiah | — | special |
| `cur-ILS` | ILS | ILS · Israeli new shekel · Israeli new shekels · new shekel · new shekels · shekel · shekels | — | special |
| `cur-IMP` | IMP | IMP | — | special |
| `cur-INR` | INR | INR · Indian rupee · Indian rupees · rupee · rupees | — | special |
| `cur-IQD` | IQD | IQD | — | special |
| `cur-IRR` | IRR | IRR | — | special |
| `cur-ISK` | ISK | ISK | — | special |
| `cur-JEP` | JEP | JEP | — | special |
| `cur-JMD` | JMD | JMD | — | special |
| `cur-JOD` | JOD | JOD · Jordanian dinar · Jordanian dinars | — | special |
| `cur-JPY` | JPY | JPY · Japanese yen · yen | — | special |
| `cur-KES` | KES | KES · Kenyan shilling · Kenyan shillings | — | special |
| `cur-KGS` | KGS | KGS | — | special |
| `cur-KHR` | KHR | KHR | — | special |
| `cur-KID` | KID | KID | — | special |
| `cur-KMF` | KMF | KMF | — | special |
| `cur-KRW` | KRW | KRW · South Korean won · Korean won · won | — | special |
| `cur-KWD` | KWD | KWD · Kuwaiti dinar · Kuwaiti dinars | — | special |
| `cur-KYD` | KYD | KYD | — | special |
| `cur-KZT` | KZT | KZT · Kazakhstani tenge · tenge | — | special |
| `cur-LAK` | LAK | LAK | — | special |
| `cur-LBP` | LBP | LBP | — | special |
| `cur-LKR` | LKR | LKR | — | special |
| `cur-LRD` | LRD | LRD | — | special |
| `cur-LSL` | LSL | LSL | — | special |
| `cur-LYD` | LYD | LYD | — | special |
| `cur-MAD` | MAD | MAD | — | special |
| `cur-MDL` | MDL | MDL | — | special |
| `cur-MGA` | MGA | MGA | — | special |
| `cur-MKD` | MKD | MKD | — | special |
| `cur-MMK` | MMK | MMK | — | special |
| `cur-MNT` | MNT | MNT | — | special |
| `cur-MOP` | MOP | MOP | — | special |
| `cur-MRU` | MRU | MRU | — | special |
| `cur-MUR` | MUR | MUR | — | special |
| `cur-MVR` | MVR | MVR | — | special |
| `cur-MWK` | MWK | MWK | — | special |
| `cur-MXN` | MXN | MXN · Mexican peso · Mexican pesos | — | special |
| `cur-MYR` | MYR | MYR · Malaysian ringgit · ringgit | — | special |
| `cur-MZN` | MZN | MZN | — | special |
| `cur-NAD` | NAD | NAD | — | special |
| `cur-NGN` | NGN | NGN · Nigerian naira · naira | — | special |
| `cur-NIO` | NIO | NIO | — | special |
| `cur-NOK` | NOK | NOK | — | special |
| `cur-NPR` | NPR | NPR | — | special |
| `cur-NZD` | NZD | NZD · New Zealand dollar · New Zealand dollars | — | special |
| `cur-OMR` | OMR | OMR | — | special |
| `cur-PAB` | PAB | PAB | — | special |
| `cur-PEN` | PEN | PEN · Peruvian sol · Peruvian soles · sol · soles | — | special |
| `cur-PGK` | PGK | PGK | — | special |
| `cur-PHP` | PHP | PHP · Philippine peso · Philippine pesos | — | special |
| `cur-PKR` | PKR | PKR · Pakistani rupee · Pakistani rupees | — | special |
| `cur-PLN` | PLN | PLN · Polish zloty · Polish zlotys · zloty · zlotys | — | special |
| `cur-PYG` | PYG | PYG | — | special |
| `cur-QAR` | QAR | QAR · Qatari riyal · Qatari riyals | — | special |
| `cur-RON` | RON | RON · Romanian leu · leu | — | special |
| `cur-RSD` | RSD | RSD | — | special |
| `cur-RUB` | RUB | RUB · Russian ruble · Russian rubles · ruble · rubles · rouble · roubles | — | special |
| `cur-RWF` | RWF | RWF | — | special |
| `cur-SAR` | SAR | SAR · Saudi riyal · Saudi riyals | — | special |
| `cur-SBD` | SBD | SBD | — | special |
| `cur-SCR` | SCR | SCR | — | special |
| `cur-SDG` | SDG | SDG | — | special |
| `cur-SEK` | SEK | SEK | — | special |
| `cur-SGD` | SGD | SGD · Singapore dollar · Singapore dollars | — | special |
| `cur-SHP` | SHP | SHP | — | special |
| `cur-SLE` | SLE | SLE | — | special |
| `cur-SLL` | SLL | SLL | — | special |
| `cur-SOS` | SOS | SOS | — | special |
| `cur-SRD` | SRD | SRD | — | special |
| `cur-SSP` | SSP | SSP | — | special |
| `cur-STN` | STN | STN | — | special |
| `cur-SYP` | SYP | SYP | — | special |
| `cur-SZL` | SZL | SZL | — | special |
| `cur-THB` | THB | THB · Thai baht · baht | — | special |
| `cur-TJS` | TJS | TJS | — | special |
| `cur-TMT` | TMT | TMT | — | special |
| `cur-TND` | TND | TND | — | special |
| `cur-TOP` | TOP | TOP | — | special |
| `cur-TRY` | TRY | TRY · Turkish lira · lira · liras | — | special |
| `cur-TTD` | TTD | TTD | — | special |
| `cur-TVD` | TVD | TVD | — | special |
| `cur-TWD` | TWD | TWD · New Taiwan dollar · New Taiwan dollars | — | special |
| `cur-TZS` | TZS | TZS | — | special |
| `cur-UAH` | UAH | UAH · Ukrainian hryvnia · hryvnia | — | special |
| `cur-UGX` | UGX | UGX | — | special |
| `cur-USD` | USD | USD · US dollar · US dollars · American dollar · American dollars · dollar · dollars | — | special |
| `cur-UYU` | UYU | UYU | — | special |
| `cur-UZS` | UZS | UZS | — | special |
| `cur-VES` | VES | VES | — | special |
| `cur-VND` | VND | VND · Vietnamese dong · dong | — | special |
| `cur-VUV` | VUV | VUV | — | special |
| `cur-WST` | WST | WST | — | special |
| `cur-XAF` | XAF | XAF | — | special |
| `cur-XCD` | XCD | XCD | — | special |
| `cur-XCG` | XCG | XCG | — | special |
| `cur-XDR` | XDR | XDR | — | special |
| `cur-XOF` | XOF | XOF | — | special |
| `cur-XPF` | XPF | XPF | — | special |
| `cur-YER` | YER | YER | — | special |
| `cur-ZAR` | ZAR | ZAR · South African rand · rand | — | special |
| `cur-ZMW` | ZMW | ZMW | — | special |
| `cur-ZWG` | ZWG | ZWG | — | special |
| `cur-ZWL` | ZWL | ZWL | — | special |

## Валюты

Каталог из 166 ISO 4217 кодов (только фиат: без криптовалют и драгметаллов; набор совпадает с открытым провайдером). Код работает как идентификатор единицы, метка и ввод-алиас. Базовая валюта по умолчанию: `USD` (настраивается в Settings → Numbers).

Цифры дробной части (ISO 4217, только отображение — значения никогда не скругляются): 0 цифр — `BIF, CLP, DJF, GNF, ISK, JPY, KMF, KRW, PYG, RWF, UGX, VND, VUV, XAF, XOF, XPF`; 3 цифры — `BHD, IQD, JOD, KWD, LYD, OMR, TND`; 4 цифры — `CLF`; во всех остальных — 2.

Ввод: маркеры (раздел «Естественные деньги»), ISO-аннотация `100 USD`, именованные алиасы ниже. Код вне каталога — неизвестная единица. Без символа в таблице маркеров отображение — суффикс кода (`600.00 CHF`); позиция символа и знака — настройки отображения.

Курсы: живой провайдер `open.er-api.com` (бесплатный эндпоинт, без ключа), базис USD; кэш «последний хороший» — атомарный файловый снимок; при офлайне или ошибке ответа приложение продолжает работать с последним кэшем, никогда не выдумывая курсы.

### Все коды

`AED` `AFN` `ALL` `AMD` `ANG` `AOA` `ARS` `AUD` `AWG` `AZN`
`BAM` `BBD` `BDT` `BGN` `BHD` `BIF` `BMD` `BND` `BOB` `BRL`
`BSD` `BTN` `BWP` `BYN` `BZD` `CAD` `CDF` `CHF` `CLF` `CLP`
`CNH` `CNY` `COP` `CRC` `CUP` `CVE` `CZK` `DJF` `DKK` `DOP`
`DZD` `EGP` `ERN` `ETB` `EUR` `FJD` `FKP` `FOK` `GBP` `GEL`
`GGP` `GHS` `GIP` `GMD` `GNF` `GTQ` `GYD` `HKD` `HNL` `HRK`
`HTG` `HUF` `IDR` `ILS` `IMP` `INR` `IQD` `IRR` `ISK` `JEP`
`JMD` `JOD` `JPY` `KES` `KGS` `KHR` `KID` `KMF` `KRW` `KWD`
`KYD` `KZT` `LAK` `LBP` `LKR` `LRD` `LSL` `LYD` `MAD` `MDL`
`MGA` `MKD` `MMK` `MNT` `MOP` `MRU` `MUR` `MVR` `MWK` `MXN`
`MYR` `MZN` `NAD` `NGN` `NIO` `NOK` `NPR` `NZD` `OMR` `PAB`
`PEN` `PGK` `PHP` `PKR` `PLN` `PYG` `QAR` `RON` `RSD` `RUB`
`RWF` `SAR` `SBD` `SCR` `SDG` `SEK` `SGD` `SHP` `SLE` `SLL`
`SOS` `SRD` `SSP` `STN` `SYP` `SZL` `THB` `TJS` `TMT` `TND`
`TOP` `TRY` `TTD` `TVD` `TWD` `TZS` `UAH` `UGX` `USD` `UYU`
`UZS` `VES` `VND` `VUV` `WST` `XAF` `XCD` `XCG` `XDR` `XOF`
`XPF` `YER` `ZAR` `ZMW` `ZWG` `ZWL`

### Именованные алиасы валют (все)

| Код | Алиасы |
|---|---|
| `AED` | `UAE dirham`, `UAE dirhams`, `dirham`, `dirhams` |
| `ARS` | `Argentine peso`, `Argentine pesos` |
| `AUD` | `Australian dollar`, `Australian dollars` |
| `BDT` | `Bangladeshi taka`, `taka` |
| `BGN` | `Bulgarian lev`, `lev` |
| `BHD` | `Bahraini dinar`, `Bahraini dinars` |
| `BRL` | `Brazilian real`, `Brazilian reais`, `reais` |
| `CAD` | `Canadian dollar`, `Canadian dollars` |
| `CHF` | `Swiss franc`, `Swiss francs` |
| `CLP` | `Chilean peso`, `Chilean pesos` |
| `CNY` | `Chinese yuan`, `yuan`, `renminbi`, `RMB` |
| `COP` | `Colombian peso`, `Colombian pesos` |
| `CZK` | `Czech koruna`, `koruna` |
| `EGP` | `Egyptian pound`, `Egyptian pounds` |
| `EUR` | `euro`, `euros`, `european euro`, `european euros` |
| `GBP` | `British pound`, `British pounds`, `pound sterling`, `sterling` |
| `GEL` | `Georgian lari`, `lari` |
| `GHS` | `Ghanaian cedi`, `cedi` |
| `HKD` | `Hong Kong dollar`, `Hong Kong dollars` |
| `HUF` | `Hungarian forint`, `forint` |
| `IDR` | `Indonesian rupiah`, `rupiah` |
| `ILS` | `Israeli new shekel`, `Israeli new shekels`, `new shekel`, `new shekels`, `shekel`, `shekels` |
| `INR` | `Indian rupee`, `Indian rupees`, `rupee`, `rupees` |
| `JOD` | `Jordanian dinar`, `Jordanian dinars` |
| `JPY` | `Japanese yen`, `yen` |
| `KES` | `Kenyan shilling`, `Kenyan shillings` |
| `KRW` | `South Korean won`, `Korean won`, `won` |
| `KWD` | `Kuwaiti dinar`, `Kuwaiti dinars` |
| `KZT` | `Kazakhstani tenge`, `tenge` |
| `MXN` | `Mexican peso`, `Mexican pesos` |
| `MYR` | `Malaysian ringgit`, `ringgit` |
| `NGN` | `Nigerian naira`, `naira` |
| `NZD` | `New Zealand dollar`, `New Zealand dollars` |
| `PEN` | `Peruvian sol`, `Peruvian soles`, `sol`, `soles` |
| `PHP` | `Philippine peso`, `Philippine pesos` |
| `PKR` | `Pakistani rupee`, `Pakistani rupees` |
| `PLN` | `Polish zloty`, `Polish zlotys`, `zloty`, `zlotys` |
| `QAR` | `Qatari riyal`, `Qatari riyals` |
| `RON` | `Romanian leu`, `leu` |
| `RUB` | `Russian ruble`, `Russian rubles`, `ruble`, `rubles`, `rouble`, `roubles` |
| `SAR` | `Saudi riyal`, `Saudi riyals` |
| `SGD` | `Singapore dollar`, `Singapore dollars` |
| `THB` | `Thai baht`, `baht` |
| `TRY` | `Turkish lira`, `lira`, `liras` |
| `TWD` | `New Taiwan dollar`, `New Taiwan dollars` |
| `UAH` | `Ukrainian hryvnia`, `hryvnia` |
| `USD` | `US dollar`, `US dollars`, `American dollar`, `American dollars`, `dollar`, `dollars` |
| `VND` | `Vietnamese dong`, `dong` |
| `ZAR` | `South African rand`, `rand` |

### Маркеры ввода

| Маркер | Код | | Маркер | Код |
|---|---|---|---|---|
| `NZ$` | `NZD` | | `CA$` | `CAD` |
| `HK$` | `HKD` | | `MX$` | `MXN` |
| `NT$` | `TWD` | | `A$` | `AUD` |
| `S$` | `SGD` | | `R$` | `BRL` |
| `CN¥` | `CNY` | | `Rp` | `IDR` |
| `RM` | `MYR` | | `zł` | `PLN` |
| `Kč` | `CZK` | | `$` | `USD` |
| `€` | `EUR` | | `£` | `GBP` |
| `¥` | `JPY` | | `₽` | `RUB` |
| `₩` | `KRW` | | `₹` | `INR` |
| `₺` | `TRY` | | `₴` | `UAH` |
| `₫` | `VND` | | `₱` | `PHP` |
| `฿` | `THB` | | `₪` | `ILS` |
| `₦` | `NGN` | | `₾` | `GEL` |
| `₸` | `KZT` | | `₮` | `MNT` |
| `₯` | `LAK` | | `៛` | `KHR` |
| `₡` | `CRC` | | `₲` | `PYG` |
| `₵` | `GHS` | |  |  |

## Сетевые запросы

Сетевые строки — строгие шаблоны; всё остальное в этих формах не «уходит в
сеть». Данные приходят от провайдеров с кэшированием; значения в этом разделе
маркируются как `[динамическое]`, потому что зависят от внешних данных и
моменту запроса.

### Погода

Точный шаблон (регистр не важен):

```text
weather in <place>
```

`<place>` — свободный текст до 100 символов; допускаются безопасная пунктуация
для однозначности (`New York`, `Paris, France`, `St. Louis`, `Côte d'Ivoire`),
пустое место, управляющие символы, токен-маркеры, `#`, `=` и операторы
(`+ - * / × ÷ − ^ % ( )`) делают строку НЕ-погодой (продолжает обычный
конвейер). Результат — текущая температура в °C (`C°`) `[динамическое]`.
Провайдер: Open-Meteo (без ключа); кэш «последнее хорошее» по каноническому
запросу (600-с TTL, затем фоновое обновление); офлайн — последнее кэшированное,
а при полном отсутствии кэша — `Weather unavailable`. Конфиденциальность:
отправляется только имя места.

### География (R85)

Точные шаблоны (регистр не важен):

```text
location of <place>
latitude of <place>
longitude of <place>
distance between <end1> and <end2>
```

Эндпоинты `distance between`: имя места (решается геокодером
`[динамическое]`) или явные координаты (офлайн, без сети). Разделитель `and`
— последний в строке, поэтому кавычки не нужны, но допускаются имена,
содержащие `and` (`distance between Rock and Roll Hall and Vienna`
расщепляется по последнему `and`). Координаты-эндпоинты: `<широта>, <долгота>`
(точка-локаль — запятая-разделитель; при десятичной-запятой локали — точка, а
пара разделяется точкой с запятой `;`). Валидные диапазоны: широта −90…90,
долгота −180…180.

Расстояние — **Haversine по поверхности** (это не маршрут и не «по дорогам»): радиус Земли —
средний WGS84 радиус 6 371 008.8 м; результат клампится в физический диапазон
[0, полукружность]; ≥ 1000 м отображается в км.

Провайдер геокодинга: Open-Meteo **только** геокодинг-эндпоинт (топ-ранговый
результат; прогноз/ключ не запрашиваются); кэш `locations.json` (30-дневный
TTL); офлайн — последнее кэшированное, затем `Location unavailable`.
Конфиденциальность: только имя места. GPS-позиция НЕ используется.

### DMS / градусы (R85)

Дорожка владеет строкой, когда: строка оканчивается ` as DMS` / ` as decimal`;
несёт prime/double-prime компоненты (DMS-запись); **или** цифра (или знак)
сидит сразу перед `°` (десятичная градусная форма, включая хвостовой кардинал).
Знаки `C°`/`F°`/`K°`/`R°` (после буквы) — температуры, никогда не перехватываются.

Формы:

| Форма | Пример | Значение |
|---|---|---|
| Десятичный градус | `51.5074°` | 51.5074 |
| + кардинал | `51.5° N`, `0.1275° W` | знак по N/S/E/W (S, W — отрицательный) |
| DMS | `156° 44′ 31.2″` | 156 + 44/60 + 31.2/3600 |
| DMS без глифов | `156 44 31` | то же (глифы опциональны) |
| Частичная DMS | `156° 44′` | минуты без секунд |
| `… as DMS` | `51.25° as DMS` | → `51° 15′ 0″` |
| `… as decimal` | `156° 44′ 31.2″ as decimal` | → 156.7419… |

Ограничения: минуты и секунды 0…59 (секунды — одна десятичная); знаки глифов
`° ′ ″` (U+00B0 U+2032 U+2033) или ASCII `'`/`''`; порядок глифов фиксирован
(первый — только `°`, второй — только `′`, третий — только `″`); компоненты 2–3.
Отображение: `156° 44′ 31.2″` (целые секунды без `.0`, десятичная-запятая
локаль — `31,2″`, отрицательные со знаком −).

## Региональные форматы чисел

Настройка «Региональный формат» (Numbers):

| Формат | Пример | Десятичный | Группировка | Разделитель аргументов функций |
|---|---|---|---|---|
| System | платформа | locale | locale | locale (запятая при запятой) |
| North America | `1,234.56` | `.` | `,` | `,` |
| Western Europe | `1.234,56` | `,` | `.` | `;` (`max(1,5; 2,5)`) |
| Eastern Europe | `1 234,56` | `,` | NBSP (пробел в вводе принимается) | `;` |

Отличия, которые важно не путать:

- Паста: при включённой «пасте с конвертацией» прилипшие группы
  (`1.234,56`) нормализуются к активному формату; без неё — побайтово.
- Группировка ввода: `1,234` вне вызовов функций — число 1234 (запятая-группа);
  десятичная-запятая как десятичный разделитель — только в западно/восточно-
  европейской конфигурации.
- Запятая/точка **внутри вызовов функций** — разделитель аргументов; при
  десятичной-запятой локали используйте `;` (`max(1,5; 2,5)`).
- Компактное отображение (`1.5M`) — отдельная настройка, не зависит от формата.
- **Язык интерфейса НЕ управляет числовой локалью.**

## Отображение чисел

Настройка «Отображение результата» (по ответу и глобально):

| Режим | Смысл |
|---|---|
| Automatic | Авто: обычный/научный/инженерный по масштабу |
| Decimal | Обычный десятичный с указанными знаками |
| Scientific | Научный (`1.5e6`) |
| Engineering | Инженерный (`1.5e6` со степенями кратно 3) |
| Fraction | Рациональная дробь (`1/2`) |
| Custom | Пользовательский паттерн (ниже) |

Доп. настройки: позиция отрицательного знака и позиции символа валюты
(префикс/суффикс, слева/справа) — применяются только к отображению.

Оверрайт на ответ: значок ответа → «Доп. знаки/формат» задаёт **локальный**
отображение; «Сброс» возвращает глобальный. Токен глобального формата не
меняется: локальный оверрайт источника НЕ переформатирует токен в других
строках.

### Пользовательский паттерн (r87)

Канонический ASCII-скелет (локаль-нейтральный; вывод локализуется
контекстом). До трёх секций через `;` — `positive;negative;zero`. Грамматика
(на секцию):

- цитированный литерал `'...'`, `''` — апостроф-эскейп;
- один числовой скелет: обязательные цифры `0`, опциональные `#`; одна точка `.`
  (в целой части `0` могут идти после `#`, в дробной — перед);
- группировка `,` только в целой части: правый сегмент — основная группа,
  одна повторённая слева — вторая (индийский стиль `#,##,##0`); остальное —
  отклоняется;
- один скалер: `%` (×100) или `‰` (×1000);
- один валютный плейсхолдер `¤` (его позиция ставит символ);
- опциональная экспонента: `E0`, `E+0`, `E00`, `E+00`, `E-00` (1–2
  экспонентных плейсхолдеров).

Пределы: 96 Unicode-скаларов на паттерн, 12 дробных плейсхолдеров, вывод
не более 256 символов. Паттерн, не прошедший валидацию, сохраняется/редактируется,
но **никогда не доходит до рендера** (fallback к предыдущему валидному).

Примеры:

```text
#,##0.00        → 1,234,565.79 (или 1.234.565,79 в запятой локали)
0.00 "€"        → 12.34 €
"$" #,##0.00    → $1,234.57
0.00%;;0        → 12.34% (положительные;отрицательные;ноль)
# ##0           → группировка по 2
#,##,##0        → индийский стиль
```

Невалидные (fallback): `1.2.3` (две точки), `#E0E0` (две экспоненты),
`0.0%‰` (два скалера), `1,000,0` (некорректная группировка).

## Answer Tokens

Создание: клик по ответу → контекстное меню → «Вставить токен» (или
`⌘`-команда). Токен — маркер U+FFFC со стабильным UUID-ссылочным идентификатором;
он ссылается на **строку-источник** (stable line ID + 1-based label), а не на
текст ответа, поэтому токен живёт при переименовании/правке строки.

Вставка:

- Курсор (или включённое выделение) на строке ≠ строка-источник: маркер
  вставляется в позицию курсора; непустое выделение заменяется маркером.
- Курсор/выделение **на самой** строке-источнике: чтобы не создать
  круговую само-ссылку, маркер падает на **новую** логическую строку сразу
  после всей строки-источника.
- Дубликаты допускаются: сколько угодно токенов на один и тот же ответ.

Поведение токена:

- Живая связь: результат источника пересчитывается → все вхождения токена
  обновляются.
- Сломанная ссылка: если строка-источник удалена, токен отображает `Line N`
  (последняя известная позиция) как недоступный.
- Поддерживаемые виды результата: скаляр (число/процент/множитель/дробь),
  количество с единицей, валюта, логический, точное целое (радианная
  презентация сохраняется), дата — как у источника.
- Конвертация единицы: `<token> to <unit>` — токен наследует количество и
  конвертируется как обычное количество.
- Копирование: токен копируется как ответ (число/единица), не как маркер.
- Локальный оверрайт отображения источника **не** меняет глобальный формат
  токена (токен отображается по своему/глобальному формату, не по локальному
  оверрайту источника).
- Целочисленная дорожка: точная форма `TOKEN & literal` (побитовая с токенным
  литералом) в текущей версии **отложена** — токен в точной дорожке
  проецируется как точный Int64 (при |v| ≤ 2^53) иначе как Double; не
  заявляйте точную побитовую арифметику над токенами как реализованную.

## Пользовательские константы (Settings → Constants)

- Имя: 1–6 ASCII-слов (первое — с буквы), ≤ 40 символов; резервированы
  категории (системные имена/категории не переопределяются).
- Выражение: **вербатим** исходный текст (≤ 256 символов) — конечное
  безразмерное скалярное число, процент, или денежное количество с одним
  фиатным кодом; может ссылаться на другие константы.
- Зависимости **независимы от порядка** объявления: значения вычисляются
  повторно чистым `ConstantResolver` на каждом проходе оценки, так как правка
  в настройках мгновенно обновляет все листы; циклическая зависимость — ошибка.
- Лимит: 100 констант.
- Область: **app-global** (настройки приложения), НЕ сохраняется в `.nlx`.
- В листе константы неизменяемы (редактируются только в Settings).

Проверенные примеры (R85):

```text
rate = 8.5
rate * 100          → 850
x = 0x1F
x & 1               → 1
x as hex            → 0x20
```

## Сводный алфавитный индекс ключевых слов

Конечные синтаксические слова → раздел. Контекстные (зависят от соседей) и
свободные (ввод-валидируемые имена мест/пользователя) помечены, поэтому
произвольные имена мест/пользователей НЕ перечислены.

| Слово | Раздел / значение | Тип |
|---|---|---|
| `a` | проценты (`as a % of`) | контекстное |
| `and` | логика/биты | контекстное |
| `as` | проценты/конвертация/база/DMS | контекстное |
| `base` | базы (`base 2`) | контекстное |
| `binary` | базы | конечное |
| `both` | — | — |
| `celsius/fahrenheit/kelvin/rankine` | температуры | конечное (единицы) |
| `day(s) week(s) month(s) year(s)` | даты/время | конечное |
| `decimal/base10` | базы | конечное |
| `degrees` | функция | функция |
| `distance` | география | контекстное |
| `dollar` и валютные имена | валюты | конечное (алиас) |
| `else` | условие | контекстное |
| `fraction` | проценты | контекстное |
| `hex/hexadecimal/base16` | базы | конечное |
| `if` | условие/проценты | контекстное |
| `in` | конвертация/rate/погода/география | контекстное |
| `int/bin/oct/hex` | функции баз | функция |
| `is` | проценты | контекстное |
| `lon/gps` | — | — |
| `location` | география | контекстное |
| `longitude` | география | контекстное |
| `of` | проценты/плотность | контекстное |
| `off/on` | проценты | контекстное |
| `or` | логика/биты | контекстное |
| `per` | ставки | контекстное |
| `percent/percentage` | проценты | контекстное |
| `radians` | функция | функция |
| `then` | условие | контекстное |
| `to` | конвертация/проценты/база | контекстное |
| `total` | команда-сумма | конечное |
| `tomorrow/today/yesterday` | даты | конечное |
| `weather` | погода | конечное |
| `what` | проценты | контекстное |
| `x` | множитель/биты | контекстное |
| `xor` | биты | контекстное |
| `per`/`in`/`at`/`of` в фразах | ставки/плотность | контекстное |

Свободный ввод (не перечисляется как «все возможные слова»): `<place>`
(погода/география, до 100 симв.), имена именованных значений/констант/кастомных
единиц (1–6 ASCII-слов ≤ 40), `<Answer Token>` (сгенерированный маркер).

## Что НЕ является синтаксисом

- **Локализация интерфейса** не меняет ни синтаксис, ни числовые разделители
  (только региональный формат — отдельно).
- **Нет GPS**: координаты только явные или геокодинг по имени.
- **Поверхность vs маршрут**: `distance between` — Haversine по сфере, не
  дорожный/воздушный маршрут.
- **Кулинарные плотности — приближённые** (версия `r84-1`), не лабораторные.
- **Отображение ≠ оценка**: формат/паттерн/знаки/символы меняют только вид,
  никогда не значение.
- **Нет AI-инференса/облака/синхронизации**: все вычисления локальные; сеть —
  только курсы, погода, геокодинг (отдельно и явно).
- Нет мультиплатформенных/мобильных/Windows/Intel-специфичных форм; приложение
  macOS (arm64).
