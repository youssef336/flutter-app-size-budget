<p align="center"><img src="https://raw.githubusercontent.com/youssef336/flutter-app-size-budget/main/screenshots/banner.png" alt="flutter-app-size-budget banner" width="100%"></p>

<h1 align="center">Flutter App Size Budget</h1>

<p align="center">
  A GitHub Action that measures your Flutter app on every pull request, comments what grew and why, and fails the check when a size budget is exceeded.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/GitHub%20Action-composite-2088FF?style=for-the-badge&logo=githubactions&logoColor=white" alt="GitHub Action">
  <img src="https://img.shields.io/badge/Dart-3.5%2B-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Flutter-analyze--size-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Android%20%7C%20iOS-apk%20%C2%B7%20aab%20%C2%B7%20ios-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Platforms">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="MIT">
</p>

> **English summary.** `youssef336/flutter-app-size-budget@v1` builds your app with
> `flutter build <apk|appbundle|ios> --analyze-size`, turns the analysis JSON plus the real artifact
> size into a small snapshot, and compares it with the baseline of the PR's base commit. The baseline
> is produced by the same action on pushes to the default branch and stored in `actions/cache`
> (plus an artifact), so a PR only builds once; set `build-base: true` to build the base commit in a
> git worktree instead. It posts **one sticky PR comment** (found by a hidden marker and updated in
> place) and the job summary: a ▲/▼ table for the total and each category (Dart AOT, Flutter engine,
> other native libs, assets, dex, resources), the biggest movers, new / removed Dart packages and a
> per-package table. Budgets come from `max-size`, `max-increase` (bytes or %) and an optional
> `size-budget.yaml` with per-category and per-package limits; a `size-increase-approved` label lets an
> intended increase through. Outputs: `status`, `total-size`, `diff-bytes`. The logic is a small Dart
> package (`tool/`) with unit tests on real `--analyze-size` output.

<div dir="rtl">

كل PR بيكبّر الـ app شوية، ومحدش بياخد باله غير لما الـ APK يبقى 80 ميجا. الـ Action ده بيبني الـ app
في كل PR، يقارنه بالـ main، ويكتب comment واحد على الـ PR فيه إيه اللي كبر وقد إيه وبسبب أنهي باكدج،
ولو عدّى الـ budget اللي حاطه بيوقع الـ check.

## ✨ بيعمل إيه

- 🏗 **بيبني** بـ `flutter build apk --release --analyze-size --target-platform android-arm64`
  (أو `appbundle`، أو `ios --no-codesign`)، ومعاه الـ flavor والـ target و `--dart-define-from-file`
  وأي arguments زيادة.
- 📦 **بيقيس** حجم الملف الحقيقي (الـ `.apk` / `.aab`، أو فولدر `Runner.app` كله في iOS)، ويقسمه:

  | الفئة | فيها إيه |
  |---|---|
  | Dart code (AOT) | `libapp.so` / `App.framework/App` |
  | Flutter engine | `libflutter.so` / `Flutter.framework` |
  | Other native libs | أي `.so` أو framework تاني (plugins) |
  | Assets | `flutter_assets` والـ fonts والـ shaders |
  | Java/Kotlin (dex) | `classes*.dex` |
  | Resources | `res/` و `resources.arsc` / `Assets.car` و storyboards |
  | Other | الباقي (`META-INF`، الـ manifest، …) |

- 🔬 **بيفصّل كود Dart بالباكدج** من الـ AOT treemap اللي Flutter بيطلّعه: `package:flutter`،
  `package:http`، `dart:io` … فتعرف إن الـ 300 KB دول جم من الباكدج الجديدة واللي هي سحبته معاها.
- 🧮 **بيقارن بالـ main**: الإجمالي، وكل فئة، والباكدجات الجديدة واللي اتشالت، و«أكبر التغييرات».
- 💬 **comment واحد بس** على الـ PR: بيدوّر عليه بـ marker مخفي ويعدّله في كل push، مش بيعمل
  comment جديد كل مرة. ونفس التقرير بيتكتب في الـ job summary.
- 🚦 **الـ budget**: حد أقصى للحجم، وحد أقصى للزيادة (بالـ bytes أو بالنسبة)، وحدود لكل فئة ولكل باكدج
  من `size-budget.yaml`. لو الزيادة مقصودة، حط label `size-increase-approved` على الـ PR والـ check يعدّي
  (والـ comment لسه بيوضّح إن فيه تجاوز).

## 🚀 الاستخدام

انسخ [`examples/size.yml`](examples/size.yml) لـ `.github/workflows/size.yml`:

</div>

```yaml
name: App size

on:
  push:
    branches: [main]            # builds and saves the baseline
  pull_request:
    types: [opened, synchronize, reopened, labeled, unlabeled]

permissions:
  contents: read
  pull-requests: write          # sticky comment
  actions: read

jobs:
  size:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }

      - uses: youssef336/flutter-app-size-budget@v1
        id: size
        with:
          platform: apk
          max-size: 30MB
          max-increase: 500KB   # or 2%
```

<div dir="rtl">

وبس كده. أول push على الـ main بيحفظ الـ baseline، وبعد كده أي PR بيتقارن بيه.
`labeled` / `unlabeled` في الـ trigger عشان الـ check يتعاد لما حد يحط الـ label.

### 📐 `size-budget.yaml` (اختياري)

حطه جنب `pubspec.yaml` (أو غيّر `budget-file`). الـ inputs `max-size` و `max-increase` بتغلب على
اللي في الفايل. الوحدات binary (‏1 MB = 1024 KB)، زي ما Flutter نفسه بيطبع. أي key غلط بيطلع error
بدل ما يتجاهل بهدوء.

</div>

```yaml
max-size: 30MB
max-increase: 2%
categories:          # dart, engine, native, assets, dex, resources, other
  assets:
    max-size: 6MB
    max-increase: 300KB
packages:            # decompressed Dart AOT size per package
  "*":
    max-increase: 200KB
  my_app:
    max-size: 4MB
```

<div dir="rtl">

## ⚙️ الـ Inputs

| Input | الافتراضي | يعني |
|---|---|---|
| `platform` | `apk` | `apk` أو `appbundle` أو `ios` (‏iOS محتاج `runs-on: macos-*`) |
| `working-directory` | `.` | فولدر الـ app لو الـ repo فيه أكتر من مشروع |
| `target-platform` | `android-arm64` | الـ ABI (الـ analyze-size محتاج واحد بس) |
| `flavor` / `target` | | `--flavor` و `--target` |
| `dart-define-from-file` | | بالنسبة لـ `working-directory` |
| `build-args` | | arguments زيادة مفصولة بمسافات |
| `max-size` | | مثلًا `25MB` |
| `max-increase` | | `500KB` أو `2%` |
| `budget-file` | `size-budget.yaml` | لو مش موجود بيتجاهله |
| `allow-label` | `size-increase-approved` | فاضي = مفيش override |
| `build-base` | `false` | يبني الـ base commit في worktree بدل الـ cache |
| `save-baseline` | `auto` | `auto` = على push للـ default branch، أو `true` / `false` |
| `comment` | `true` | الـ sticky comment |
| `comment-id` | `platform[-flavor]` | يفصل الـ comments والـ baselines لو عندك أكتر من job |
| `top-packages` | `10` | كام باكدج في جدول التفاصيل |
| `fail-on-budget` | `true` | `false` = تقرير و warning بس |
| `github-token` | `github.token` | محتاج `pull-requests: write` |
| `setup-flutter` | `false` | يسطّب Flutter بـ `subosito/flutter-action@v2` لو الـ workflow مش عامل كده |
| `flutter-version` / `flutter-channel` | `''` / `stable` | لـ `setup-flutter` |

## 📤 الـ Outputs

| Output | يعني |
|---|---|
| `status` | `pass` أو `fail` أو `approved` (عدّى الـ budget بس عليه الـ label) |
| `total-size` | حجم الـ artifact بالـ bytes |
| `diff-bytes` | الفرق عن الـ baseline (فاضي لو مفيش baseline) |
| `base-size` | حجم الـ baseline |
| `baseline` | جه منين: `exact` أو `fallback` أو `built` أو `missing` |
| `report-path` / `snapshot-path` | الـ Markdown والـ snapshot JSON بتوع الـ run ده |

## 🧠 الـ baseline بيتجاب منين

1. **push على الـ default branch**: الـ Action بيبني ويحفظ snapshot صغير (JSON) في `actions/cache`
   بمفتاح فيه الـ commit sha، وكمان كـ artifact اسمه `flutter-size-baseline-<id>`.
2. **PR**: بيرجّع الـ snapshot بتاع الـ base sha بالظبط (`exact`). لو مش موجود (الـ run بتاع الـ main
   لسه مخلصش مثلًا) بياخد آخر baseline محفوظ للـ branch (`fallback`)، والـ comment بيقول كده صراحة.
3. **`build-base: true`**: بيعمل `git worktree` للـ base commit ويبنيه هو كمان (`built`). دقيق دايمًا،
   بس بيضاعف وقت البناء.

## 💸 التكلفة على GitHub Actions

- بناء Android على `ubuntu-latest` بياخد تقريبًا **5 لـ 10 دقايق** لكل run (حسب حجم المشروع والـ cache)،
  و `build-base: true` بيضاعفهم.
- **iOS لازم macOS runner، ودقيقته بـ 10 دقايق** من رصيدك في الـ repos الـ private. لو رصيدك محدود
  خلّي iOS على `workflow_dispatch` أو على الـ PRs اللي فيها label بس.

## ❓ أسئلة

<details>
<summary><b>ليه مجموع الفئات مش بالظبط حجم الـ APK؟</b></summary>

الفئات هي حجم كل ملف **مضغوط جوه** الـ zip، والفرق هو headers الـ zip نفسه (كام KB). الـ budget بيتحسب
دايمًا على حجم الملف الحقيقي.
</details>

<details>
<summary><b>ليه أحجام باكدجات Dart أكبر من فئة Dart code؟</b></summary>

أحجام الباكدجات من الـ AOT snapshot **قبل الضغط** (زي ما Flutter DevTools بيعرضها)، فهي للمقارنة بين
الباكدجات وبعض، مش عشان تتجمع على الإجمالي. وكمان `dart:*` و `@stubs` و `@unknown` و `@vm` حاجات
الـ runtime بتاعة Dart نفسها، ومفيش باكدج بعينها مسؤولة عنها.
</details>

<details>
<summary><b>إضافة باكدج واحدة كبّرت <code>dart:io</code> و <code>dart:_http</code>، ليه؟</b></summary>

لأن الـ tree shaking بيشيل اللي مش مستخدم من مكتبات Dart نفسها. لما `package:http` اتضافت، الأجزاء
اللي بتستخدمها من `dart:io` بقت جوه الـ app. ده الطبيعي، وده اللي «أكبر التغييرات» بيوضحه.
</details>

<details>
<summary><b>الـ PR جاي من fork والـ comment مش بيتكتب</b></summary>

الـ `GITHUB_TOKEN` في الـ PRs اللي من forks بيكون read-only، فالـ comment بيفشل بـ warning بس والتقرير
بيفضل في الـ job summary. الـ check نفسه شغال عادي.
</details>

<details>
<summary><b>عندي apk و ios في نفس الـ PR</b></summary>

اعمل job لكل واحد. الـ `comment-id` الافتراضي هو `platform[-flavor]`، فكل واحد ليه comment وbaseline
لوحده. لو عندك أكتر من app بنفس الـ platform (monorepo)، اديهم `comment-id` مختلف.
</details>

<details>
<summary><b>الـ size اللي بيقيسه هو حجم التحميل من Play Store؟</b></summary>

لأ. ده حجم الـ APK اللي اتبنى لـ ABI واحد (‏`android-arm64`)، وهو قريب من اللي المستخدم بينزّله بس مش
هو بالظبط. لـ `appbundle` بيقيس ملف الـ `.aab` نفسه. المهم هنا الفرق بين الـ PR والـ main، وده دقيق.
</details>

## ⚖️ الحدود

- `--analyze-size` بيبني release build كامل، فالـ Action مش بيوفّر وقت البناء. لو عندك job بيبني
  release أصلًا، الأرخص إنك تخلي ده هو الـ job.
- بيقيس ABI واحد بس (قيد من Flutter نفسه: الـ analyze-size محتاج `--target-platform` واحد).
- الـ cache بتاع GitHub بيتمسح بعد 7 أيام من غير استخدام أو لو عدّى 10 GB، ساعتها الـ PR بياخد
  `fallback` أو `missing` لحد ما يحصل push جديد على الـ main.
- `build-args` بتتقسم على المسافات بس (مفيش quotes).
- iOS بيتبني `--no-codesign` وبيتقاس `Runner.app` مش الـ `.ipa`، وفئة «Other native libs» في iOS
  معناها frameworks تانية غير Flutter.
- اتجرّب على Flutter 3.47 (Android و iOS). صيغة الـ JSON جاية من `analyze_size.dart` في flutter_tools،
  ولو Flutter غيّرها في نسخة جاية ممكن يحتاج تعديل.

</div>

## 🛠 Tech stack

- Composite GitHub Action (`action.yml`) + Bash (`scripts/build.sh`) for the build.
- Dart package in `tool/` (`args`, `yaml`), run with `dart run` using the Dart that ships with Flutter.
- `actions/cache` (restore / save) for baselines, `actions/upload-artifact`, `gh api` for the sticky comment.
- Unit tests with `package:test` on real `--analyze-size` output (apk pair + iOS) from Flutter 3.47.

## 🏗 Project structure

| File | Role |
|---|---|
| `action.yml` | inputs, outputs and the steps (build, restore / build baseline, report, comment, enforce) |
| `scripts/build.sh` | runs `flutter build … --analyze-size` and keeps the log |
| `tool/lib/src/snapshot.dart` | analyze-size JSON → categories, Dart packages, native libs |
| `tool/lib/src/diff.dart` | base vs head: totals, categories, packages, biggest movers |
| `tool/lib/src/budget.dart` | `size-budget.yaml` + inputs → violations |
| `tool/lib/src/report.dart` | status, step outputs and the Markdown comment |
| `tool/lib/src/github.dart` | find-and-update sticky comment through `gh api` |
| `tool/lib/src/build_output.dart` | finds the analysis JSON and the artifact in the build log |
| `tool/test/` | unit + CLI tests; `fixtures/` holds real (trimmed) analysis files |
| `examples/` | a copy-ready workflow and budget file |

## 🧪 Development

```bash
cd tool
dart pub get
dart test
dart format --line-length 120 .
```

## 📄 License

[MIT](LICENSE)

## 👤 Author

**Youssef Belal Zakaria** · [GitHub @youssef336](https://github.com/youssef336)

⭐ If you like this project, give it a star!
