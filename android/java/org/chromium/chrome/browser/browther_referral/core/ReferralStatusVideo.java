// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.regex.Pattern;

/**
 * La **vidéo** du statut WhatsApp — `private/docs/PARRAINAGE.md` § 11, port de
 * `BrowtherReferral/ReferralStatusVideo.swift` (iOS, la référence ; elle-même portée de
 * `fajrunaa/lib/referral/statusVideo.ts`, recettée sur iPhone par Karim le 2026-10-08). Jumeau du
 * site : `website/lib/statusVideo.ts` (page `/share`).
 *
 * <p>La feuille « Partager mon code » propose DEUX statuts : la vidéo de présentation de Browther
 * (la même pour tout le monde) et l'image qui porte le code de la personne. Elle coche ce qu'elle
 * veut publier.
 *
 * <h2>Un envoi par statut</h2>
 *
 * <p>WhatsApp ne donne le texte partagé qu'au PREMIER média d'un envoi, et range les médias à sa
 * façon (constat iPhone du 2026-10-07, cinq arrangements essayés). Le seul qui garde le lien sous
 * CHAQUE statut, dans l'ordre voulu : **un envoi par statut**, chacun avec son lien. ⛔ Ne pas
 * revenir à un envoi groupé « pour gagner un geste » : le second statut partirait sans lien. ⭐ Le
 * second envoi part tout seul après un court décompte ANNONCÉ par la jauge du bouton ({@link
 * #NEXT_AUTO_MS}) — un tap le devance. ⛔ Jamais sans la jauge : rouvrir WhatsApp sans prévenir se
 * lit comme un défaut.
 *
 * <h2>La vidéo n'est pas dans l'app</h2>
 *
 * <p>~5 Mo par langue : elle est téléchargée depuis le site, qui publie un **manifeste** (une vidéo
 * par langue). Chacun n'a besoin que de SA langue, la plupart ne partagent jamais, et la vidéo se
 * change — ou se COUPE — sans release ({@code {"v": 1, "videos": {}}}).
 *
 * <p>🔴 **Tout ce fichier est fail-open** : pas de manifeste, entrée malformée, langue absente ⇒
 * {@code null}, et la feuille ne propose que l'image — le geste d'avant, à l'identique. ⛔ Rien ici
 * ne doit pouvoir empêcher de publier.
 *
 * <p>Pur ({@code java.*} seul) : testé dans `private/scripts/android-referral-tests/`.
 */
public final class ReferralStatusVideo {
    private ReferralStatusVideo() {}

    /** Les deux statuts. {@code rawValue} = la valeur de {@code referral_shared.media}. */
    public enum Segment {
        VIDEO("video"),
        IMAGE("image");

        public final String rawValue;

        Segment(String rawValue) {
            this.rawValue = rawValue;
        }
    }

    /** Un oui ou un non par statut : ce qui est coché, ce qui est déjà parti. */
    public static final class Flags {
        public final boolean video;
        public final boolean image;

        public Flags(boolean video, boolean image) {
            this.video = video;
            this.image = image;
        }

        public static final Flags BOTH = new Flags(true, true);
        public static final Flags NONE = new Flags(false, false);

        /** Sans vidéo, une seule chose à publier : l'image, d'office. */
        public static final Flags IMAGE_ONLY = new Flags(false, true);

        public boolean get(Segment segment) {
            return segment == Segment.VIDEO ? video : image;
        }

        /** Les mêmes drapeaux, avec celui de {@code segment} posé à {@code value}. */
        public Flags with(Segment segment, boolean value) {
            return segment == Segment.VIDEO ? new Flags(value, image) : new Flags(video, value);
        }

        @Override
        public boolean equals(Object other) {
            if (!(other instanceof Flags)) return false;
            Flags o = (Flags) other;
            return video == o.video && image == o.image;
        }

        @Override
        public int hashCode() {
            return (video ? 2 : 0) + (image ? 1 : 0);
        }

        @Override
        public String toString() {
            return "Flags(video: " + video + ", image: " + image + ")";
        }
    }

    /** Ce que dit le bouton — UN bouton, qui publie toujours le prochain statut de la file. */
    public static final class Cta {
        public enum Kind {
            /** Les deux sont cochés, rien n'est parti. */
            BOTH,
            /** Un seul est coché, rien n'est parti. */
            ONE,
            /** Un statut est parti, il reste celui-ci (« 2 sur 2 »). */
            NEXT,
            /** Rien n'est coché : le bouton est éteint. */
            NONE,
            /** Tout ce qui était coché est parti : la feuille se referme. */
            DONE
        }

        public final Kind kind;

        /** Le statut que le bouton publie — {@code null} hors de {@code ONE} et {@code NEXT}. */
        public final Segment segment;

        private Cta(Kind kind, Segment segment) {
            this.kind = kind;
            this.segment = segment;
        }

        public static Cta both() {
            return new Cta(Kind.BOTH, null);
        }

        public static Cta one(Segment segment) {
            return new Cta(Kind.ONE, segment);
        }

        public static Cta next(Segment segment) {
            return new Cta(Kind.NEXT, segment);
        }

        public static Cta none() {
            return new Cta(Kind.NONE, null);
        }

        public static Cta done() {
            return new Cta(Kind.DONE, null);
        }

        @Override
        public boolean equals(Object other) {
            if (!(other instanceof Cta)) return false;
            Cta o = (Cta) other;
            return kind == o.kind && segment == o.segment;
        }

        @Override
        public int hashCode() {
            return Objects.hash(kind, segment);
        }

        @Override
        public String toString() {
            return segment == null ? kind.name() : kind.name() + "(" + segment.rawValue + ")";
        }
    }

    /** Une vidéo du manifeste : son adresse, et sa taille EXACTE. */
    public static final class Entry {
        public final String url;
        public final int bytes;

        public Entry(String url, int bytes) {
            this.url = url;
            this.bytes = bytes;
        }

        @Override
        public boolean equals(Object other) {
            if (!(other instanceof Entry)) return false;
            Entry o = (Entry) other;
            return bytes == o.bytes && url.equals(o.url);
        }

        @Override
        public int hashCode() {
            return Objects.hash(url, bytes);
        }

        @Override
        public String toString() {
            return "Entry(" + url + ", " + bytes + ")";
        }
    }

    /** Le manifeste, sur le site du produit (un hôte que l'app appelle déjà). */
    public static final String MANIFEST_URL = ReferralProduct.siteURL + "/share-status/manifest.json";

    /**
     * Au-delà, WhatsApp REFUSE la vidéo en statut (16 Mo). Une entrée plus lourde est écartée :
     * mieux vaut l'image seule qu'un statut rejeté.
     */
    public static final int MAX_BYTES = 16_000_000;

    /**
     * Combien de temps la feuille attend la vidéo avant de s'en passer. Elle est demandée dès que
     * « Partager mon code » est à l'écran : ce délai ne se voit que sur une connexion lente, et il
     * ne doit jamais retenir quelqu'un qui veut publier.
     */
    public static final long WAIT_MS = 8_000;

    /**
     * Le décompte avant que le second statut parte tout seul. Court, mais assez long pour LIRE
     * « Publié » et voir la jauge avancer — donc pour refermer la feuille si on n'en veut pas.
     */
    public static final long NEXT_AUTO_MS = 3_000;

    /**
     * ⚠️ Un succès n'est mémorisé que dix minutes : le manifeste est aussi l'interrupteur qui COUPE
     * la vidéo, et Android garde un navigateur en mémoire des jours.
     */
    public static final long FRESH_MS = 600_000;

    /**
     * ⭐ **L'ordre des deux statuts — la SEULE source** : celui des vignettes ET celui des envois
     * (verrouillé par test). La vidéo d'abord : elle accroche et explique ; l'image ensuite porte
     * l'offre et l'appel au clic.
     */
    public static final List<Segment> SEGMENTS =
            Collections.unmodifiableList(Arrays.asList(Segment.VIDEO, Segment.IMAGE));

    /** Les langues dans lesquelles l'image du statut existe ({@code ReferralStatusImage.Texts}). */
    public static final List<String> IMAGE_LANGUAGES =
            Collections.unmodifiableList(Arrays.asList("fr", "en", "ar"));

    /**
     * ⭐ **La vidéo suit la langue de l'IMAGE** (Karim, 2026-10-08) : Browther a ~60 langues
     * d'interface et l'image n'existe qu'en fr, en et ar — les autres la reçoivent en anglais, donc
     * la vidéo aussi. ⛔ Aucun autre repli : la règle « pas de vidéo dans une autre langue que
     * l'image » tient toujours.
     */
    public static String statusLanguage(String appLanguage) {
        String base = base(appLanguage);
        return IMAGE_LANGUAGES.contains(base) ? base : "en";
    }

    /** « fr-BE », « AR », « zh_TW » → « fr », « ar », « zh ». */
    private static String base(String language) {
        String lowered = language == null ? "" : language.toLowerCase(Locale.ROOT);
        for (String part : lowered.split("[-_]")) {
            if (!part.isEmpty()) return part;
        }
        return lowered;
    }

    /**
     * ⛔ Rien d'autre qu'un {@code .mp4} en HTTPS servi par dev&din : le manifeste ne doit pas
     * pouvoir faire télécharger n'importe quoi, de n'importe où.
     */
    private static final Pattern URL_PATTERN =
            Pattern.compile("https://([a-z0-9-]+\\.)+devndin\\.com/[A-Za-z0-9/._-]+\\.mp4");

    private static Entry entry(Object raw) {
        if (!(raw instanceof Map)) return null;
        Map<?, ?> object = (Map<?, ?>) raw;
        Object url = object.get("url");
        if (!(url instanceof String)) return null;
        // ⚠️ Seul un nombre ENTIER est une taille : ni « true », ni « "12" », ni 1,5.
        Object bytes = object.get("bytes");
        double value;
        if (bytes instanceof Long) {
            value = (Long) bytes;
        } else if (bytes instanceof Double) {
            value = (Double) bytes;
        } else {
            return null;
        }
        if (Double.isNaN(value) || Double.isInfinite(value) || value != Math.rint(value)) return null;
        if (value <= 0 || value > MAX_BYTES) return null;
        String address = (String) url;
        if (!URL_PATTERN.matcher(address).matches() || address.contains("..")) return null;
        return new Entry(address, (int) value);
    }

    /**
     * Lecture défensive du texte reçu : une entrée malformée est jetée, jamais tout le manifeste ;
     * un document illisible (ou pas de réponse : {@code null}) rend « aucune vidéo ».
     */
    public static Map<String, Entry> manifest(String json) {
        if (json == null) return Collections.emptyMap();
        try {
            return manifestFromJson(ReferralJson.parse(json));
        } catch (ReferralJson.JsonException e) {
            return Collections.emptyMap();
        }
    }

    /** La même lecture, sur un document déjà lu ({@link ReferralJson#parse}). */
    public static Map<String, Entry> manifestFromJson(Object raw) {
        if (!(raw instanceof Map)) return Collections.emptyMap();
        Object videos = ((Map<?, ?>) raw).get("videos");
        if (!(videos instanceof Map)) return Collections.emptyMap();
        Map<String, Entry> out = new LinkedHashMap<>();
        for (Map.Entry<?, ?> item : ((Map<?, ?>) videos).entrySet()) {
            Entry entry = entry(item.getValue());
            if (entry != null) {
                out.put(String.valueOf(item.getKey()).toLowerCase(Locale.ROOT), entry);
            }
        }
        return out;
    }

    /**
     * La vidéo d'une langue. ⛔ Pas de repli ICI : l'appelant passe la langue de l'image ({@link
     * #statusLanguage}), et sans vidéo dans cette langue l'image part seule.
     */
    public static Entry pick(Map<String, Entry> manifest, String language) {
        return manifest.get(base(language));
    }

    /**
     * Le nom du fichier en cache = le dernier segment de l'URL. Une vidéo changée porte un autre nom
     * ({@code …-2.mp4}) : l'ancienne n'est jamais relue par erreur.
     */
    public static String fileName(Entry entry) {
        String last = entry.url.substring(entry.url.lastIndexOf('/') + 1);
        StringBuilder out = new StringBuilder(last.length());
        for (int i = 0; i < last.length(); i++) {
            char c = last.charAt(i);
            boolean keep =
                    (c >= 'a' && c <= 'z')
                            || (c >= 'A' && c <= 'Z')
                            || (c >= '0' && c <= '9')
                            || c == '.'
                            || c == '_'
                            || c == '-';
            out.append(keep ? c : '_');
        }
        return out.toString();
    }

    /**
     * Le fichier en cache est-il LA vidéo ? ⚠️ Un transfert interrompu laisse un fichier court que le
     * système déclare présent : seule la taille exacte du manifeste fait foi. {@code size == null}
     * = pas de fichier.
     */
    public static boolean isComplete(Entry entry, Long size) {
        return size != null && size == entry.bytes;
    }

    /** Les statuts que la feuille propose : les deux, ou l'image seule faute de vidéo. */
    public static List<Segment> segments(boolean hasVideo) {
        return hasVideo ? SEGMENTS : Collections.singletonList(Segment.IMAGE);
    }

    /** Ce qui reste à publier, dans l'ordre des statuts : coché, et pas encore parti. */
    public static List<Segment> queue(Flags picked, Flags sent) {
        List<Segment> out = new ArrayList<>();
        for (Segment segment : SEGMENTS) {
            if (picked.get(segment) && !sent.get(segment)) out.add(segment);
        }
        return out;
    }

    public static Cta cta(Flags picked, Flags sent) {
        List<Segment> queue = queue(picked, sent);
        boolean sentAny = false;
        for (Segment segment : SEGMENTS) sentAny |= sent.get(segment);
        if (queue.isEmpty()) return sentAny ? Cta.done() : Cta.none();
        if (queue.size() > 1) return Cta.both();
        return sentAny ? Cta.next(queue.get(0)) : Cta.one(queue.get(0));
    }
}
