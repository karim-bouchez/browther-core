// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Le statut complet d'un sujet — le contrat avec le service de parrainage (`docs/PARRAINAGE.md` §
 * 7 et § 10.3, contrat détaillé dans `referral/docs/API.md`).
 *
 * <p>⚠️ **Cette classe ne décide de rien** : elle traduit les réponses du service en types. Les
 * règles vivent dans {@link AccessState} (ce qui est ouvert), {@link MilestoneScale} (les paliers)
 * et {@link ReferralPrompt} (quand solliciter).
 *
 * <p>⛔ **Aucun texte utilisateur ici** : le service renvoie un *cas* de rappel, l'app choisit la
 * phrase.
 *
 * <p>🔴 **Le mot `referral` est déjà pris dans le fork** (`brave_referrals`, le programme de codes
 * promo d'installation de Brave) : tout ce qui est à nous vit dans `browther_referral`, sous des
 * clés `browther.referral.*`.
 *
 * <p>Les champs sont modifiables (comme les `var` d'une structure Swift) ; {@link #copy()} rend une
 * copie indépendante, et l'égalité est celle du contenu.
 */
public final class ReferralStatus {
    public static final class Access {
        public boolean unlocked;
        public boolean lifetime;
        public String until;
        public AccessSource source;

        public Access(boolean unlocked, boolean lifetime, String until, AccessSource source) {
            this.unlocked = unlocked;
            this.lifetime = lifetime;
            this.until = until;
            this.source = source;
        }

        static Access fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
            AccessSource source = AccessSource.fromRaw(o.string("source"));
            if (source == null) throw new ReferralJson.JsonException("source d'accès inconnue");
            return new Access(o.bool("unlocked"), o.bool("lifetime"), o.optString("until"), source);
        }

        Map<String, Object> toJson() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("unlocked", unlocked);
            m.put("lifetime", lifetime);
            m.put("until", until);
            m.put("source", source.rawValue);
            return m;
        }
    }

    /** ⭐ « Qui a payé n'est plus jamais sollicité » (§ 4), tant que ça court. */
    public static final class Subscription {
        public boolean active;
        public boolean everPaid;
        public boolean willRenew;
        public String until;

        public Subscription(boolean active, boolean everPaid, boolean willRenew, String until) {
            this.active = active;
            this.everPaid = everPaid;
            this.willRenew = willRenew;
            this.until = until;
        }

        static Subscription fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
            return new Subscription(
                    o.bool("active"), o.bool("everPaid"), o.bool("willRenew"), o.optString("until"));
        }

        Map<String, Object> toJson() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("active", active);
            m.put("everPaid", everPaid);
            m.put("willRenew", willRenew);
            m.put("until", until);
            return m;
        }
    }

    /** Le mois de l'annonce (écran 0) — {@code startedAt == null} = pas encore démarré. */
    public static final class Trial {
        public String startedAt;

        public Trial(String startedAt) {
            this.startedAt = startedAt;
        }

        static Trial fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
            return new Trial(o.optString("startedAt"));
        }

        Map<String, Object> toJson() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("startedAt", startedAt);
            return m;
        }
    }

    public static final class Referral {
        public String code;
        /** {@code null} tant que la régie n'a pas créé le lien : on partage le code seul. */
        public String url;
        public Integer clicks;

        public Referral(String code, String url, Integer clicks) {
            this.code = code;
            this.url = url;
            this.clicks = clicks;
        }

        static Referral fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
            return new Referral(o.string("code"), o.optString("url"), o.optInteger("clicks"));
        }

        Map<String, Object> toJson() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("code", code);
            m.put("url", url);
            m.put("clicks", clicks);
            return m;
        }
    }

    public static final class Invitations {
        public int sent;
        public int installed;
        public int validated;
        public List<InvitationItem> items;

        public Invitations(int sent, int installed, int validated, List<InvitationItem> items) {
            this.sent = sent;
            this.installed = installed;
            this.validated = validated;
            this.items = items;
        }

        static Invitations fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
            List<InvitationItem> items = new ArrayList<>();
            for (Object item : o.array("items")) {
                items.add(InvitationItem.fromJson(ReferralJson.Obj.of(item)));
            }
            return new Invitations(
                    o.integer("sent"), o.integer("installed"), o.integer("validated"), items);
        }

        Map<String, Object> toJson() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("sent", sent);
            m.put("installed", installed);
            m.put("validated", validated);
            List<Object> list = new ArrayList<>();
            for (InvitationItem item : items) list.add(item.toJson());
            m.put("items", list);
            return m;
        }
    }

    public static final class Milestones {
        public static final class Next {
            public int at;
            public int bonusMonths;
            public int remaining;
            public boolean lifetime;

            public Next(int at, int bonusMonths, int remaining, boolean lifetime) {
                this.at = at;
                this.bonusMonths = bonusMonths;
                this.remaining = remaining;
                this.lifetime = lifetime;
            }

            static Next fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
                return new Next(
                        o.integer("at"),
                        o.integer("bonusMonths"),
                        o.integer("remaining"),
                        o.bool("lifetime"));
            }

            Map<String, Object> toJson() {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("at", at);
                m.put("bonusMonths", bonusMonths);
                m.put("remaining", remaining);
                m.put("lifetime", lifetime);
                return m;
            }
        }

        public int validated;
        public int monthsEarned;
        public int lifetimeAt;
        public Next next;

        /** Le barème complet du produit (brief B bis) — absent d'un service antérieur. */
        public List<MilestoneBonus> bonuses;

        public Milestones(
                int validated,
                int monthsEarned,
                int lifetimeAt,
                Next next,
                List<MilestoneBonus> bonuses) {
            this.validated = validated;
            this.monthsEarned = monthsEarned;
            this.lifetimeAt = lifetimeAt;
            this.next = next;
            this.bonuses = bonuses;
        }

        static Milestones fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
            ReferralJson.Obj next = o.optObj("next");
            List<Object> raw = o.optArray("bonuses");
            List<MilestoneBonus> bonuses = null;
            if (raw != null) {
                bonuses = new ArrayList<>();
                for (Object item : raw) bonuses.add(MilestoneBonus.fromJson(ReferralJson.Obj.of(item)));
            }
            return new Milestones(
                    o.integer("validated"),
                    o.integer("monthsEarned"),
                    o.integer("lifetimeAt"),
                    next == null ? null : Next.fromJson(next),
                    bonuses);
        }

        Map<String, Object> toJson() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("validated", validated);
            m.put("monthsEarned", monthsEarned);
            m.put("lifetimeAt", lifetimeAt);
            m.put("next", next == null ? null : next.toJson());
            if (bonuses == null) {
                m.put("bonuses", null);
            } else {
                List<Object> list = new ArrayList<>();
                for (MilestoneBonus bonus : bonuses) list.add(bonus.toJson());
                m.put("bonuses", list);
            }
            return m;
        }
    }

    public static final class Reminder {
        /**
         * Le cas de rappel (`case` côté service — mot réservé en Java). ⚠️ Un cas inconnu (service
         * plus récent que l'app) vaut « rien à dire », ⛔ pas un statut illisible : sinon tout le
         * parrainage tomberait.
         */
        public ReminderCase reminderCase;

        public String nextCoverageEnd;

        public Reminder(ReminderCase reminderCase, String nextCoverageEnd) {
            this.reminderCase = reminderCase;
            this.nextCoverageEnd = nextCoverageEnd;
        }

        static Reminder fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
            return new Reminder(
                    ReminderCase.fromRaw(o.optString("case")), o.optString("nextCoverageEnd"));
        }

        Map<String, Object> toJson() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("case", reminderCase == null ? null : reminderCase.rawValue);
            m.put("nextCoverageEnd", nextCoverageEnd);
            return m;
        }
    }

    /**
     * ⭐ Ce que voit celui qui a SAISI un code (§ 5.3). {@code null} = pas de parrain. ⛔ Rien du
     * parrain n'y figure : ni identifiant, ni code, ni date.
     */
    public static final class ReferredBy {
        public enum Status {
            INSTALLED("installed"),
            VALIDATED("validated");

            public final String rawValue;

            Status(String rawValue) {
                this.rawValue = rawValue;
            }

            public static Status fromRaw(String raw) {
                for (Status value : values()) {
                    if (value.rawValue.equals(raw)) return value;
                }
                return null;
            }
        }

        public Status status;
        public String redeemedAt;
        public String validatedAt;
        public ValidationProgress progress;

        public ReferredBy(
                Status status, String redeemedAt, String validatedAt, ValidationProgress progress) {
            this.status = status;
            this.redeemedAt = redeemedAt;
            this.validatedAt = validatedAt;
            this.progress = progress;
        }

        static ReferredBy fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
            Status status = Status.fromRaw(o.string("status"));
            if (status == null) throw new ReferralJson.JsonException("statut de filleul inconnu");
            ReferralJson.Obj progress = o.optObj("progress");
            return new ReferredBy(
                    status,
                    o.optString("redeemedAt"),
                    o.optString("validatedAt"),
                    progress == null ? null : ValidationProgress.fromJson(progress));
        }

        Map<String, Object> toJson() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("status", status.rawValue);
            m.put("redeemedAt", redeemedAt);
            m.put("validatedAt", validatedAt);
            m.put("progress", progress == null ? null : progress.toJson());
            return m;
        }
    }

    /** Le critère à atteindre côté filleul (§ 5.2). */
    public static final class Validation {
        public String kind;
        public String event;
        public double target;

        public Validation(String kind, String event, double target) {
            this.kind = kind;
            this.event = event;
            this.target = target;
        }

        static Validation fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
            return new Validation(o.string("kind"), o.string("event"), o.number("target"));
        }

        Map<String, Object> toJson() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("kind", kind);
            m.put("event", event);
            m.put("target", target);
            return m;
        }
    }

    public String product;
    public String serverTime;
    public Access access;
    public Subscription subscription;
    public Trial trial;
    public Referral referral;
    public Invitations invitations;
    public Milestones milestones;
    public Reminder reminder;
    public ReferredBy referredBy;
    public Validation validation;

    private ReferralStatus() {}

    // MARK: - JSON

    public static ReferralStatus fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
        ReferralStatus s = new ReferralStatus();
        s.product = o.string("product");
        s.serverTime = o.optString("serverTime");
        s.access = Access.fromJson(o.obj("access"));
        s.subscription = Subscription.fromJson(o.obj("subscription"));
        s.trial = Trial.fromJson(o.obj("trial"));
        s.referral = Referral.fromJson(o.obj("referral"));
        s.invitations = Invitations.fromJson(o.obj("invitations"));
        s.milestones = Milestones.fromJson(o.obj("milestones"));
        s.reminder = Reminder.fromJson(o.obj("reminder"));
        ReferralJson.Obj referredBy = o.optObj("referredBy");
        s.referredBy = referredBy == null ? null : ReferredBy.fromJson(referredBy);
        ReferralJson.Obj validation = o.optObj("validation");
        s.validation = validation == null ? null : Validation.fromJson(validation);
        return s;
    }

    public static ReferralStatus fromJson(String text) throws ReferralJson.JsonException {
        return fromJson(ReferralJson.parseObject(text));
    }

    public Map<String, Object> toJson() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("product", product);
        m.put("serverTime", serverTime);
        m.put("access", access.toJson());
        m.put("subscription", subscription.toJson());
        m.put("trial", trial.toJson());
        m.put("referral", referral.toJson());
        m.put("invitations", invitations.toJson());
        m.put("milestones", milestones.toJson());
        m.put("reminder", reminder.toJson());
        m.put("referredBy", referredBy == null ? null : referredBy.toJson());
        m.put("validation", validation == null ? null : validation.toJson());
        return m;
    }

    /** Une copie indépendante (la sémantique « valeur » de la structure Swift). */
    public ReferralStatus copy() {
        try {
            return fromJson(ReferralJson.parseObject(ReferralJson.stringify(toJson())));
        } catch (ReferralJson.JsonException e) {
            throw new IllegalStateException("un statut lu se relit toujours", e);
        }
    }

    @Override
    public boolean equals(Object other) {
        return other instanceof ReferralStatus && toJson().equals(((ReferralStatus) other).toJson());
    }

    @Override
    public int hashCode() {
        return toJson().hashCode();
    }

    // MARK: - Ce que le statut dit de l'accès

    /**
     * ⭐ « Qui a payé n'est plus jamais sollicité » (§ 4, absolu).
     *
     * <p>⚠️ Un abonnement **résilié mais encore courant** n'en fait pas partie : c'est précisément
     * le cas de rappel `subscription_cancelled` (§ 3.3).
     */
    public boolean isSubscriberAtPeace() {
        return subscription.active && subscription.willRenew;
    }

    /**
     * 🔴 **Statut effectif = max(accès payé LOCAL, couverture du service)** (§ 7.4). L'achat du
     * magasin est connu de l'appareil avant le service : le webhook arrive quelques secondes après.
     * ⚠️ `willRenew` vient aussi de l'appareil : un abonnement résilié mais courant ne doit pas
     * passer pour « en paix ». (Android n'a pas encore de paiement — § 12.27, porte factice — : sans
     * achat local, le statut est rendu tel quel.)
     */
    public ReferralStatus merging(LocalEntitlement entitlement) {
        if (entitlement == null || !entitlement.active || subscription.active) return this;
        ReferralStatus merged = copy();
        merged.access.unlocked = true;
        merged.access.source = AccessSource.PAID;
        if (entitlement.until != null) {
            merged.access.until = ReferralDate.string(entitlement.until);
        }
        Instant until = entitlement.until;
        merged.subscription =
                new Subscription(
                        true,
                        true,
                        entitlement.willRenew,
                        until == null ? null : ReferralDate.string(until));
        return merged;
    }
}
