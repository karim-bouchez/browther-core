/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * L'image du <b>statut WhatsApp</b> qui porte le code (1080 × 1920) — port de {@code
 * ReferralStatusImage} iOS, jumeau de {@code website/lib/statusImage.ts} (le même dessin, validé par
 * Karim sur Sawtunaa le 2026-09-29). Décision commune : {@code
 * devndin/docs/PARRAINAGE-partage-statut.md}.
 *
 * <p>De haut en bas : le texte au « tu » (au pluriel en arabe), style surligneur · la carte B9
 * inclinée (−4°, +4° en arabe), ⛔ SANS lien ni « Copier » · l'étiquette « Clique sur le lien en
 * dessous 👇 », droite, posée juste au-dessus de la légende — qui ne contient QUE le lien ({@link
 * ReferralSharing#shareStatusFile} : l'image + le lien en texte).
 *
 * <p>🔴 WhatsApp pose la légende PAR-DESSUS le bas de l'image, et « N vues » dessous : ~250 px du
 * bas sont couverts (recette iPhone Sawtunaa du 2026-09-29). L'étiquette est à 270 px du bas — ⛔ ne
 * pas la redescendre.
 *
 * <p>Police : celle du système (Roboto, Noto pour l'arabe) — ⚠️ le site dessine en Inter Tight /
 * Alexandria, iOS en SF : mêmes cotes, lignes coupées un peu différemment.
 */
public final class ReferralStatusImage {
    public static final int WIDTH = 1080;
    public static final int HEIGHT = 1920;
    private static final float MARGIN = 72;
    private static final int SAGE = 0xFF5F7454;
    private static final int GOLD = 0xFFC4A572;

    private ReferralStatusImage() {}

    /**
     * Les textes DANS l'image — {@code PARRAINAGE-partage-statut.md} § 3 et § 5, mot pour mot ceux
     * d'iOS ({@code Strings.BrowtherReferral.StatusImage}) et du site ({@code
     * sharePage.statusImage}). ⚠️ <b>Hors de la table traduite, exprès</b> : l'image n'existe qu'en
     * fr, en et ar (décision du 2026-09-28 : une police par écriture n'en vaut pas le coût tant
     * qu'on n'a pas mesuré), les autres langues retombent sur l'anglais.
     *
     * <p>{@code [[…]]} = surligné (sauge), {@code {{…}}} = surligné or (l'accès à vie), le seuil de
     * l'accès à vie vient du barème ({@code lifetimeAt}, ⛔ jamais en dur). 🔴 ⛔ Jamais « gratuit »
     * pour le mois offert. Arabe : au PLURIEL (un statut parle à tout le monde, le singulier
     * imposerait un genre).
     */
    public static final class Texts {
        public final String language;
        public final String[] paragraphs;
        public final String sticker;
        public final String cardLabel;
        public final String cardTab;
        public final String cardOmni;
        public final String cardGift;
        public final String tag;

        /**
         * « Mon code : {code} » — la ligne du message envoyé à un proche (onglet « Message » de la
         * feuille de partage, private/docs/PARRAINAGE.md § 11). ⚠️ Ici et pas dans la table
         * traduite : elle suit le texte de l'image, donc SA langue (fr, en, ar) — un message ne
         * mélange pas deux langues.
         */
        public final String codeLine;

        private Texts(
                String language,
                String[] paragraphs,
                String sticker,
                String cardLabel,
                String cardTab,
                String cardOmni,
                String cardGift,
                String tag,
                String codeLine) {
            this.language = language;
            this.paragraphs = paragraphs;
            this.sticker = sticker;
            this.cardLabel = cardLabel;
            this.cardTab = cardTab;
            this.cardOmni = cardOmni;
            this.cardGift = cardGift;
            this.tag = tag;
            this.codeLine = codeLine;
        }

        /** {@link #codeLine}, le code posé à sa place. */
        public String codeLine(String code) {
            return codeLine.replace("{code}", code);
        }

        public boolean isRtl() {
            return "ar".equals(language);
        }

        /** Les textes dans la langue de l'app (fr, en ou ar ; sinon l'anglais). */
        public static Texts current(Context context, int lifetimeAt) {
            return of(ReferralFormat.locale(context).getLanguage(), lifetimeAt);
        }

        public static Texts of(String language, int lifetimeAt) {
            String life = String.valueOf(lifetimeAt);
            switch (language == null ? "" : language.toLowerCase(Locale.ROOT)) {
                case "fr":
                    return new Texts(
                            "fr",
                            new String[] {
                                "Si toi aussi tu cherches à naviguer sur [[internet sans musique ni"
                                        + " images haram]], essaie ce navigateur : il supprime toute"
                                        + " musique et floute les hommes et/ou les femmes. Dispo sur"
                                        + " mobile et PC.",
                                "Avec mon code, tu as [[un mois de fonctionnalités bonus]].",
                                "Et si " + life + " personnes l'installent avec ton code, tu as"
                                        + " tout de {{débloqué à vie}} !",
                            },
                            "Clique sur le lien en dessous 👇",
                            "Mon code",
                            "Parrainage",
                            "Musique coupée · images floutées",
                            "1 mois de bonus",
                            "Un projet",
                            "Mon code : {code}");
                case "ar":
                    return new Texts(
                            "ar",
                            new String[] {
                                "إذا كنتم تبحثون أنتم أيضًا عن تصفّح [[الإنترنت بلا موسيقى ولا صور"
                                        + " محرّمة]]، جرّبوا هذا المتصفّح: يحذف كل الموسيقى ويموّه صور"
                                        + " الرجال و/أو النساء. متوفّر على الجوال والكمبيوتر.",
                                "برمزي، تحصلون على [[شهر من الميزات الإضافية]].",
                                "وإذا ثبّته " + life + " أشخاص برمزكم، تُفتح لكم {{كل الميزات مدى"
                                        + " الحياة}}!",
                            },
                            "اضغطوا على الرابط في الأسفل 👇",
                            "رمزي",
                            "التزكية",
                            "الموسيقى مقطوعة · الصور مموّهة",
                            "شهر من الميزات",
                            "مشروع من",
                            "رمزي: {code}");
                default:
                    return new Texts(
                            "en",
                            new String[] {
                                "If you're also looking to browse [[the internet without music or"
                                        + " haram images]], try this browser: it removes all music"
                                        + " and blurs men and/or women. Available on mobile and PC.",
                                "With my code, you get [[a month of bonus features]].",
                                "And if " + life + " people install it with your code, you get"
                                        + " {{everything unlocked for life}}!",
                            },
                            "Tap the link below 👇",
                            "My code",
                            "Referrals",
                            "Music off · images blurred",
                            "1 month of bonus",
                            "A project by",
                            "My code: {code}");
            }
        }
    }

    /** L'image, opaque (réencodée en JPEG par l'appelant : ~300 Ko au lieu de plusieurs Mo). */
    public static Bitmap render(Context context, String code, Texts texts) {
        boolean rtl = texts.isRtl();
        Bitmap bitmap = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        canvas.drawColor(0xFF131316);
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(0xFFFFFFFF);
        paint.setShader(
                new RadialGradient(
                        WIDTH / 2f, HEIGHT * 0.36f, WIDTH * 0.95f,
                        0x4D7C916F, 0x007C916F,
                        Shader.TileMode.CLAMP));
        canvas.drawRect(0, 0, WIDTH, HEIGHT, paint);
        paint.setShader(null);

        // Le haut reste libre : WhatsApp y pose le nom et l'heure.
        float textBottom = drawParagraphs(canvas, texts.paragraphs, rtl, 170);

        // L'étiquette, droite, juste au-dessus de la légende (le lien).
        Paint sticker = new Paint(Paint.ANTI_ALIAS_FLAG);
        sticker.setTextSize(54);
        sticker.setTypeface(Typeface.create(Typeface.DEFAULT, 800, false));
        sticker.setColor(0xFF121212);
        float stickerWidth = sticker.measureText(texts.sticker);
        float stW = stickerWidth + 64;
        float stH = 54 * 1.75f;
        float stY = HEIGHT - 270 - stH;
        RectF stRect = new RectF((WIDTH - stW) / 2, stY, (WIDTH + stW) / 2, stY + stH);
        paint.setColor(0xFFFFFFFF);
        paint.setShadowLayer(20, 0, 16, 0x59000000);
        canvas.drawRoundRect(stRect, 26, 26, paint);
        paint.clearShadowLayer();
        Paint.FontMetrics fm = sticker.getFontMetrics();
        canvas.drawText(
                texts.sticker,
                stRect.centerX() - stickerWidth / 2,
                stRect.centerY() - (fm.ascent + fm.descent) / 2 + 2,
                sticker);

        // La carte, inclinée, dans l'espace entre le texte et l'étiquette.
        float room = stY - 70 - (textBottom + 90);
        float cw = Math.max(560, Math.min(860, room / (1 / 1.586f + 0.12f)));
        float ch = cw * ReferralCardFace.HEIGHT / ReferralCardFace.WIDTH;
        float cy = textBottom + 90 + (room - ch) / 2 + ch / 2;
        ReferralCardFace face =
                ReferralCardFace.status(
                        context,
                        code,
                        texts.cardOmni,
                        texts.cardGift,
                        texts.cardTab,
                        texts.cardLabel,
                        texts.tag,
                        rtl);
        float scale = cw / ReferralCardFace.WIDTH;
        canvas.save();
        canvas.translate(WIDTH / 2f, cy);
        canvas.rotate(rtl ? 4 : -4);
        canvas.translate(-cw / 2, -ch / 2);
        paint.setColor(0xFF0F1110);
        paint.setShadowLayer(35, 0, 36, 0xA6000000);
        canvas.drawRoundRect(new RectF(0, 0, cw, ch), 18 * scale, 18 * scale, paint);
        paint.clearShadowLayer();
        canvas.scale(scale, scale);
        face.draw(canvas, -1f);
        canvas.restore();
        return bitmap;
    }

    // -------------------- Le texte, style surligneur --------------------

    private static final int NONE = 0;
    private static final int HIGHLIGHT = 1;
    private static final int GOLD_MARK = 2;

    private static final class Word {
        final String text;
        final int mark;
        /** Collé au mot d'avant, sans espace (« bonus]]. » → le point suit le surligné). */
        final boolean glue;

        float width;
        float x0;

        Word(String text, int mark, boolean glue) {
            this.text = text;
            this.mark = mark;
            this.glue = glue;
        }
    }

    /** {@code [[a]] b {{c}}} → mots marqués. Même découpe que {@code parseWords} du site. */
    static List<Word> words(String paragraph) {
        List<Word> result = new ArrayList<>();
        String rest = paragraph;
        boolean previousEndsWithSpace = true;
        while (!rest.isEmpty()) {
            String chunk;
            int mark;
            int close;
            if (rest.startsWith("[[") && (close = rest.indexOf("]]")) >= 0) {
                chunk = rest.substring(2, close);
                mark = HIGHLIGHT;
                rest = rest.substring(close + 2);
            } else if (rest.startsWith("{{") && (close = rest.indexOf("}}")) >= 0) {
                chunk = rest.substring(2, close);
                mark = GOLD_MARK;
                rest = rest.substring(close + 2);
            } else {
                int a = rest.indexOf("[[");
                int b = rest.indexOf("{{");
                int next = rest.length();
                if (a >= 0) next = Math.min(next, a);
                if (b >= 0) next = Math.min(next, b);
                int stop = next == 0 ? 1 : next;
                chunk = rest.substring(0, stop);
                mark = NONE;
                rest = rest.substring(stop);
            }
            boolean glueFirst = !previousEndsWithSpace && !chunk.startsWith(" ");
            String[] pieces = chunk.split(" ", -1);
            for (int i = 0; i < pieces.length; i++) {
                if (pieces[i].isEmpty()) continue;
                result.add(new Word(pieces[i], mark, i == 0 && glueFirst && !result.isEmpty()));
            }
            previousEndsWithSpace = chunk.endsWith(" ");
        }
        return result;
    }

    /**
     * Le texte, mot à mot : le surligné se pose derrière des groupes de mots, ligne par ligne.
     * Rend la ligne de base de la dernière ligne.
     */
    private static float drawParagraphs(Canvas canvas, String[] paragraphs, boolean rtl, float top) {
        float fontSize = rtl ? 46 : 50;
        float lineHeight = fontSize * (rtl ? 1.75f : 1.42f);
        float paragraphGap = fontSize * 0.8f;
        float maxWidth = WIDTH - 2 * MARGIN;
        Paint font = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG);
        font.setTextSize(fontSize);
        font.setTypeface(Typeface.create(Typeface.DEFAULT, 700, false));
        float space = font.measureText(" ");
        float pad = fontSize * 0.18f;
        Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        RectF rect = new RectF();
        float y = top;

        for (String paragraph : paragraphs) {
            List<Word> measured = words(paragraph);
            for (Word word : measured) word.width = font.measureText(word.text);
            List<List<Word>> lines = new ArrayList<>();
            List<Word> current = new ArrayList<>();
            float currentWidth = 0;
            for (Word word : measured) {
                float next =
                        current.isEmpty()
                                ? word.width
                                : currentWidth + (word.glue ? 0 : space) + word.width;
                if (!current.isEmpty() && next > maxWidth - pad * 2) {
                    lines.add(current);
                    current = new ArrayList<>();
                    current.add(word);
                    currentWidth = word.width;
                } else {
                    current.add(word);
                    currentWidth = next;
                }
            }
            if (!current.isEmpty()) lines.add(current);

            for (List<Word> line : lines) {
                y += lineHeight;
                // Position de chaque mot (de droite à gauche en arabe).
                float x = rtl ? WIDTH - MARGIN - pad : MARGIN + pad;
                int previous = -1; // aucun mot encore
                for (int i = 0; i < line.size(); i++) {
                    Word word = line.get(i);
                    int prev = previous < 0 ? NONE : previous;
                    boolean changes =
                            word.mark != previous && (word.mark != NONE || prev != NONE);
                    float edge = changes ? pad : 0;
                    float gap = i == 0 ? 0 : (word.glue ? edge : space + edge);
                    previous = word.mark;
                    float x0 = rtl ? x - gap - word.width : x + gap;
                    x = rtl ? x0 : x0 + word.width;
                    word.x0 = x0;
                }
                // Les surlignés : un bloc par suite de mots de même marque.
                int i = 0;
                while (i < line.size()) {
                    int mark = line.get(i).mark;
                    int j = i;
                    while (j + 1 < line.size() && line.get(j + 1).mark == mark) j++;
                    if (mark != NONE) {
                        Word a = line.get(i);
                        Word b = line.get(j);
                        float left = Math.min(a.x0, b.x0);
                        float right = Math.max(a.x0 + a.width, b.x0 + b.width);
                        rect.set(
                                left - pad,
                                y - fontSize * 0.98f,
                                right + pad,
                                y - fontSize * 0.98f + fontSize * 1.3f);
                        fill.setColor(mark == GOLD_MARK ? GOLD : SAGE);
                        canvas.drawRoundRect(rect, fontSize * 0.16f, fontSize * 0.16f, fill);
                    }
                    i = j + 1;
                }
                for (Word word : line) {
                    font.setColor(word.mark == GOLD_MARK ? 0xFF16191A : 0xFFFFFFFF);
                    canvas.drawText(word.text, word.x0, y, font);
                }
            }
            y += paragraphGap;
        }
        return y - paragraphGap;
    }
}
