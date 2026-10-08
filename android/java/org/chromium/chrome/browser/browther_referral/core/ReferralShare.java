// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.nio.charset.StandardCharsets;

/**
 * Le message d'invitation — `docs/PARRAINAGE.md` § 12.10.
 *
 * <p>⭐ La forme retenue par Karim, dans cet ordre : ce qu'est l'app · le code et ce qu'il apporte ·
 * **le lien, seul sur la dernière ligne**.
 *
 * <p>🔴 **Le lien est DANS le texte, ⛔ pas un élément à part de la feuille de partage** : chaque
 * cible le placerait où elle veut (en tête, en aperçu détaché, ou nulle part). 🔴 **⛔ Pas de sujet
 * non plus** (§ 12.10) : il se colle en tête du message dans certaines cibles (`EXTRA_SUBJECT` sur
 * Android). ⚠️ **Le lien traqué peut manquer** le temps que la régie le crée : on termine alors par
 * le site, avec le code en `?ref=`. ⛔ Jamais un message qui ne mène nulle part.
 */
public final class ReferralShare {
    private ReferralShare() {}

    /** Le lien d'invitation : le lien traqué, sinon le site avec le code. */
    public static String link(String code, String url) {
        if (url != null && !url.isEmpty()) return url;
        StringBuilder encoded = new StringBuilder();
        for (byte b : code.getBytes(StandardCharsets.UTF_8)) {
            char c = (char) (b & 0xff);
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
                encoded.append(c);
            } else {
                encoded.append(String.format("%%%02X", b & 0xff));
            }
        }
        return ReferralProduct.siteURL + "/?ref=" + encoded;
    }

    /**
     * Le message complet : {@code text} (déjà dans la langue de la personne, avec le code), puis le
     * lien seul sur la dernière ligne.
     */
    public static String message(String text, String code, String url) {
        return text + "\n" + link(code, url);
    }

    // MARK: - Le message qui accompagne un fichier (onglet « Message », § 11 du doc du produit)

    /** Retire les marques de surlignage de l'image du statut ({@code [[…]]}, {@code {{…}}}). */
    public static String stripStatusMarks(String text) {
        return text.replace("[[", "").replace("]]", "").replace("{{", "").replace("}}", "");
    }

    /**
     * Le message qui accompagne la **VIDÉO** (Karim, 2026-10-08) : le texte de l'IMAGE du statut,
     * en clair — une seule source pour ce qu'on dit du produit —, puis le code VISIBLE (sur l'image
     * il est sur la carte ; ici il n'y a pas de carte), et le lien seul sur la dernière ligne.
     */
    public static String videoMessage(String[] paragraphs, String codeLine, String code, String url) {
        StringBuilder body = new StringBuilder();
        for (String paragraph : paragraphs) {
            if (body.length() > 0) body.append("\n\n");
            body.append(stripStatusMarks(paragraph));
        }
        return body + "\n\n" + codeLine + "\n" + link(code, url);
    }

    /**
     * Le message qui accompagne l'**IMAGE** du statut, quand la vidéo est décochée. L'image dit
     * déjà tout : il ne reste que le code, en texte qu'on peut copier, et le lien juste dessous.
     */
    public static String imageMessage(String codeLine, String code, String url) {
        return codeLine + "\n" + link(code, url);
    }
}
