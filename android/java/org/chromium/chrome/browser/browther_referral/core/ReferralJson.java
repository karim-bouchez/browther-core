// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Le JSON du parrainage — lecture et écriture, ⛔ sans `org.json` : le module doit tourner sur la
 * JVM du Mac, où `android.jar` ne contient que des bouchons (`private/scripts/android-referral-
 * tests/run.sh`). C'est l'équivalent de `JSONDecoder`/`JSONEncoder` côté iOS.
 *
 * <p>Représentation : objet = {@code Map<String, Object>} (ordre conservé, une clé présente à
 * {@code null} ≠ une clé absente), tableau = {@code List<Object>}, chaîne = {@code String}, nombre
 * = {@code Long} s'il est entier, {@code Double} sinon, booléen = {@code Boolean}, `null` = {@code
 * null}.
 *
 * <p>⚠️ **Strict** : un document mal formé, un contenu en trop après la valeur, un nombre hors
 * grammaire JSON sont refusés ({@link JsonException}) — ⛔ jamais « lu à moitié ».
 */
public final class ReferralJson {
    private ReferralJson() {}

    /** Un document illisible, ou une réponse qui n'a pas la forme du contrat. */
    public static final class JsonException extends Exception {
        public JsonException(String message) {
            super(message);
        }
    }

    // MARK: - Lecture

    public static Object parse(String text) throws JsonException {
        if (text == null) throw new JsonException("document vide");
        Parser parser = new Parser(text);
        parser.skipWhitespace();
        Object value = parser.value(0);
        parser.skipWhitespace();
        if (parser.pos != text.length()) {
            throw new JsonException("contenu en trop à la position " + parser.pos);
        }
        return value;
    }

    /** Un document dont la racine DOIT être un objet (toutes les réponses du service). */
    public static Obj parseObject(String text) throws JsonException {
        return Obj.of(parse(text));
    }

    private static final class Parser {
        private static final int MAX_DEPTH = 64;
        private final String s;
        int pos;

        Parser(String s) {
            this.s = s;
        }

        void skipWhitespace() {
            while (pos < s.length()) {
                char c = s.charAt(pos);
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                    pos++;
                } else {
                    break;
                }
            }
        }

        private JsonException error(String what) {
            return new JsonException(what + " à la position " + pos);
        }

        Object value(int depth) throws JsonException {
            if (depth > MAX_DEPTH) throw error("imbrication trop profonde");
            if (pos >= s.length()) throw error("fin inattendue");
            char c = s.charAt(pos);
            switch (c) {
                case '{':
                    return object(depth);
                case '[':
                    return array(depth);
                case '"':
                    return string();
                case 't':
                    literal("true");
                    return Boolean.TRUE;
                case 'f':
                    literal("false");
                    return Boolean.FALSE;
                case 'n':
                    literal("null");
                    return null;
                default:
                    if (c == '-' || (c >= '0' && c <= '9')) return number();
                    throw error("caractère inattendu « " + c + " »");
            }
        }

        private void literal(String word) throws JsonException {
            if (!s.startsWith(word, pos)) throw error("littéral invalide");
            pos += word.length();
        }

        private Map<String, Object> object(int depth) throws JsonException {
            Map<String, Object> map = new LinkedHashMap<>();
            pos++; // {
            skipWhitespace();
            if (pos < s.length() && s.charAt(pos) == '}') {
                pos++;
                return map;
            }
            while (true) {
                skipWhitespace();
                if (pos >= s.length() || s.charAt(pos) != '"') throw error("clé attendue");
                String key = string();
                skipWhitespace();
                if (pos >= s.length() || s.charAt(pos) != ':') throw error("« : » attendu");
                pos++;
                skipWhitespace();
                if (map.containsKey(key)) throw error("clé en double « " + key + " »");
                map.put(key, value(depth + 1));
                skipWhitespace();
                if (pos >= s.length()) throw error("fin inattendue");
                char c = s.charAt(pos++);
                if (c == '}') return map;
                if (c != ',') throw error("« , » ou « } » attendu");
            }
        }

        private List<Object> array(int depth) throws JsonException {
            List<Object> list = new ArrayList<>();
            pos++; // [
            skipWhitespace();
            if (pos < s.length() && s.charAt(pos) == ']') {
                pos++;
                return list;
            }
            while (true) {
                skipWhitespace();
                list.add(value(depth + 1));
                skipWhitespace();
                if (pos >= s.length()) throw error("fin inattendue");
                char c = s.charAt(pos++);
                if (c == ']') return list;
                if (c != ',') throw error("« , » ou « ] » attendu");
            }
        }

        private String string() throws JsonException {
            pos++; // "
            StringBuilder out = new StringBuilder();
            while (true) {
                if (pos >= s.length()) throw error("chaîne non terminée");
                char c = s.charAt(pos++);
                if (c == '"') return out.toString();
                if (c < 0x20) throw error("caractère de contrôle dans une chaîne");
                if (c != '\\') {
                    out.append(c);
                    continue;
                }
                if (pos >= s.length()) throw error("échappement non terminé");
                char e = s.charAt(pos++);
                switch (e) {
                    case '"':
                        out.append('"');
                        break;
                    case '\\':
                        out.append('\\');
                        break;
                    case '/':
                        out.append('/');
                        break;
                    case 'b':
                        out.append('\b');
                        break;
                    case 'f':
                        out.append('\f');
                        break;
                    case 'n':
                        out.append('\n');
                        break;
                    case 'r':
                        out.append('\r');
                        break;
                    case 't':
                        out.append('\t');
                        break;
                    case 'u':
                        if (pos + 4 > s.length()) throw error("\\u incomplet");
                        int code = 0;
                        for (int i = 0; i < 4; i++) {
                            int digit = Character.digit(s.charAt(pos + i), 16);
                            if (digit < 0) throw error("\\u invalide");
                            code = code * 16 + digit;
                        }
                        pos += 4;
                        out.append((char) code);
                        break;
                    default:
                        throw error("échappement inconnu « \\" + e + " »");
                }
            }
        }

        private Object number() throws JsonException {
            int start = pos;
            if (s.charAt(pos) == '-') pos++;
            if (pos >= s.length()) throw error("nombre incomplet");
            if (s.charAt(pos) == '0') {
                pos++;
            } else if (s.charAt(pos) >= '1' && s.charAt(pos) <= '9') {
                while (pos < s.length() && Character.isDigit(s.charAt(pos))) pos++;
            } else {
                throw error("nombre invalide");
            }
            boolean integral = true;
            if (pos < s.length() && s.charAt(pos) == '.') {
                integral = false;
                pos++;
                int digits = pos;
                while (pos < s.length() && isAsciiDigit(s.charAt(pos))) pos++;
                if (pos == digits) throw error("décimales attendues");
            }
            if (pos < s.length() && (s.charAt(pos) == 'e' || s.charAt(pos) == 'E')) {
                integral = false;
                pos++;
                if (pos < s.length() && (s.charAt(pos) == '+' || s.charAt(pos) == '-')) pos++;
                int digits = pos;
                while (pos < s.length() && isAsciiDigit(s.charAt(pos))) pos++;
                if (pos == digits) throw error("exposant attendu");
            }
            String text = s.substring(start, pos);
            if (integral) {
                try {
                    return Long.parseLong(text);
                } catch (NumberFormatException tooBig) {
                    // Au-delà d'un long : lu en double, comme n'importe quel nombre.
                }
            }
            return Double.parseDouble(text);
        }

        private static boolean isAsciiDigit(char c) {
            return c >= '0' && c <= '9';
        }
    }

    // MARK: - Écriture

    /** Le texte JSON d'une valeur (Map, List, String, Number, Boolean, null). */
    public static String stringify(Object value) {
        StringBuilder out = new StringBuilder();
        write(value, out);
        return out.toString();
    }

    private static void write(Object value, StringBuilder out) {
        if (value == null) {
            out.append("null");
        } else if (value instanceof String) {
            writeString((String) value, out);
        } else if (value instanceof Boolean) {
            out.append(((Boolean) value) ? "true" : "false");
        } else if (value instanceof Integer || value instanceof Long) {
            out.append(((Number) value).longValue());
        } else if (value instanceof Number) {
            double d = ((Number) value).doubleValue();
            if (Double.isNaN(d) || Double.isInfinite(d)) {
                throw new IllegalArgumentException("nombre non représentable en JSON : " + d);
            }
            if (d == Math.rint(d) && Math.abs(d) < 1e15) {
                out.append((long) d);
            } else {
                out.append(d);
            }
        } else if (value instanceof Map) {
            out.append('{');
            boolean first = true;
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) value).entrySet()) {
                if (!first) out.append(',');
                first = false;
                writeString(String.valueOf(entry.getKey()), out);
                out.append(':');
                write(entry.getValue(), out);
            }
            out.append('}');
        } else if (value instanceof List) {
            out.append('[');
            boolean first = true;
            for (Object item : (List<?>) value) {
                if (!first) out.append(',');
                first = false;
                write(item, out);
            }
            out.append(']');
        } else {
            throw new IllegalArgumentException("type non sérialisable : " + value.getClass());
        }
    }

    private static void writeString(String text, StringBuilder out) {
        out.append('"');
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            switch (c) {
                case '"':
                    out.append("\\\"");
                    break;
                case '\\':
                    out.append("\\\\");
                    break;
                case '\n':
                    out.append("\\n");
                    break;
                case '\r':
                    out.append("\\r");
                    break;
                case '\t':
                    out.append("\\t");
                    break;
                default:
                    if (c < 0x20) {
                        out.append(String.format("\\u%04x", (int) c));
                    } else {
                        out.append(c);
                    }
            }
        }
        out.append('"');
    }

    // MARK: - Lecture typée

    /**
     * Un objet JSON, lu champ par champ. ⚠️ Un champ REQUIS absent, nul ou du mauvais type lève
     * {@link JsonException} (comme un `Codable` non optionnel) ; un champ OPTIONNEL absent ou nul
     * vaut {@code null}, mais du mauvais type il lève aussi.
     */
    public static final class Obj {
        private final Map<String, Object> map;

        private Obj(Map<String, Object> map) {
            this.map = map;
        }

        @SuppressWarnings("unchecked")
        public static Obj of(Object value) throws JsonException {
            if (!(value instanceof Map)) throw new JsonException("objet attendu");
            return new Obj((Map<String, Object>) value);
        }

        public Map<String, Object> map() {
            return Collections.unmodifiableMap(map);
        }

        public boolean has(String key) {
            return map.containsKey(key);
        }

        public boolean isNull(String key) {
            return map.get(key) == null;
        }

        private Object required(String key) throws JsonException {
            Object value = map.get(key);
            if (value == null) throw new JsonException("champ requis absent : " + key);
            return value;
        }

        public String string(String key) throws JsonException {
            Object value = required(key);
            if (!(value instanceof String)) throw new JsonException("chaîne attendue : " + key);
            return (String) value;
        }

        public String optString(String key) throws JsonException {
            return map.get(key) == null ? null : string(key);
        }

        public boolean bool(String key) throws JsonException {
            Object value = required(key);
            if (!(value instanceof Boolean)) throw new JsonException("booléen attendu : " + key);
            return (Boolean) value;
        }

        public Boolean optBool(String key) throws JsonException {
            return map.get(key) == null ? null : bool(key);
        }

        public double number(String key) throws JsonException {
            Object value = required(key);
            if (!(value instanceof Number)) throw new JsonException("nombre attendu : " + key);
            return ((Number) value).doubleValue();
        }

        public Double optNumber(String key) throws JsonException {
            return map.get(key) == null ? null : number(key);
        }

        /** Un entier — ⚠️ un nombre à virgule est refusé, comme `Int` en Swift. */
        public int integer(String key) throws JsonException {
            Object value = required(key);
            if (value instanceof Long) {
                long l = (Long) value;
                if (l >= Integer.MIN_VALUE && l <= Integer.MAX_VALUE) return (int) l;
            } else if (value instanceof Double) {
                double d = (Double) value;
                if (d == Math.rint(d) && d >= Integer.MIN_VALUE && d <= Integer.MAX_VALUE) {
                    return (int) d;
                }
            }
            throw new JsonException("entier attendu : " + key);
        }

        public Integer optInteger(String key) throws JsonException {
            return map.get(key) == null ? null : integer(key);
        }

        public Obj obj(String key) throws JsonException {
            return of(required(key));
        }

        public Obj optObj(String key) throws JsonException {
            return map.get(key) == null ? null : obj(key);
        }

        @SuppressWarnings("unchecked")
        public List<Object> array(String key) throws JsonException {
            Object value = required(key);
            if (!(value instanceof List)) throw new JsonException("tableau attendu : " + key);
            return (List<Object>) value;
        }

        public List<Object> optArray(String key) throws JsonException {
            return map.get(key) == null ? null : array(key);
        }
    }
}
