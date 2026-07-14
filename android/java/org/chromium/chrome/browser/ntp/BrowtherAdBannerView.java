/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.ntp;

import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.util.AttributeSet;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;

import androidx.annotation.Nullable;
import androidx.viewpager2.widget.ViewPager2;

import com.bumptech.glide.RequestManager;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_ads.BrowtherAdsBridge;
import org.chromium.chrome.browser.util.TabUtils;
import org.chromium.ui.base.ViewUtils;

import java.util.HashSet;
import java.util.Set;

/**
 * Bannière pub devndin-ads sur le NTP (mobile : au-dessus des favoris, entre
 * les stats et les favoris — parité iOS {@code BrowtheAdSectionProvider}).
 * Carousel paginé, aspect-ratio piloté par le champ {@code ratio} du serve
 * (parité desktop {@code browther_ad_banner.tsx}). Label « Pub » par slide si
 * {@code showAdLabel} (annonceur externe — cf. INTEGRATION.md § 3).
 *
 * <p>Le serve (mode public X-Publisher-Id, throttlé ~10 min), le batching des
 * impressions et la résolution du click URL vivent dans
 * {@link BrowtherAdsBridge} (client C++). Seuls {@code id}, {@code imageUrl},
 * {@code ratio} et {@code showAdLabel} arrivent ici.
 *
 * <p>Impression à visibilité réelle (parité IntersectionObserver desktop / iOS
 * {@code didMarkInitial}) : on ne signale une page que lorsque la bannière est
 * réellement attachée au viewport ({@link #onAttachedToWindow()}) et à chaque
 * settle de page ({@code onPageSelected}). Idempotent par {@code id} (Set local
 * + déduplication côté client C++).
 */
public class BrowtherAdBannerView extends LinearLayout {
    // Ratio de secours si le serve ne renvoie pas de champ `ratio` exploitable
    // (vieux cache serveur). L'aspect-ratio nominal est piloté par le champ
    // renvoyé — jamais de valeur en dur (ads/docs/INTEGRATION.md § 3).
    private static final float FALLBACK_AD_RATIO = 3.2f;

    // Headroom réservé au-dessus de la créa pour l'onglet label « à cheval »
    // sur le bord haut (parité desktop `.ad-label { top: -10px }`). Doit rester
    // synchronisé avec le `paddingTop` de browther_ad_banner_item.xml : le pager
    // est rallongé de ce headroom pour que l'image garde son ratio (l'image =
    // hauteur du pager moins le padding de la page).
    private static final int LABEL_HEADROOM_DP = 10;

    private ViewPager2 mPager;
    private LinearLayout mDots;
    private BrowtherAdsBridge.Ad[] mAds = new BrowtherAdsBridge.Ad[0];
    // Pubs déjà signalées visibles dans cette instance (le client C++ dédup aussi).
    private final Set<String> mMarkedVisible = new HashSet<>();
    private boolean mAttached;
    private int mPagerHeight;
    // Aspect-ratio courant (largeur/hauteur), issu du champ `ratio` du serve.
    private float mAdRatio = FALLBACK_AD_RATIO;

    public BrowtherAdBannerView(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
    }

    @Override
    protected void onFinishInflate() {
        super.onFinishInflate();
        mPager = findViewById(R.id.browther_ad_pager);
        mDots = findViewById(R.id.browther_ad_dots);
        // Gap visible entre deux créas pendant le swipe (INTEGRATION.md § 3
        // « UX carousel — mobile natif », slides pleine largeur + gap ~12 px).
        mPager.setPageTransformer(
                new androidx.viewpager2.widget.MarginPageTransformer(
                        ViewUtils.dpToPx(getContext(), 12)));
        mPager.registerOnPageChangeCallback(
                new ViewPager2.OnPageChangeCallback() {
                    @Override
                    public void onPageSelected(int position) {
                        updateDots(position);
                        if (mAttached) {
                            markVisible(position);
                        }
                    }
                });
    }

    /**
     * Renseigne les pubs servies + le {@link RequestManager} Glide pour charger
     * les images. Reconfigure le carousel (idempotent).
     */
    public void setAds(BrowtherAdsBridge.Ad[] ads, RequestManager glide) {
        mAds = ads != null ? ads : new BrowtherAdsBridge.Ad[0];
        mMarkedVisible.clear();
        // Aspect-ratio piloté par le serve (le placement a un format unique,
        // toutes les pubs du lot partagent le même ratio). Reset du cache de
        // hauteur pour re-mesurer si le format a changé.
        mAdRatio = parseRatio(mAds.length > 0 ? mAds[0].ratio : null);
        mPagerHeight = 0;
        mPager.setAdapter(new BrowtherAdPagerAdapter(mAds, glide, this::onAdClicked));
        buildDots(mAds.length);
        updateDots(0);
        // Rebind alors que déjà visible (notifyItemChanged) → impression directe.
        if (mAttached && mAds.length > 0) {
            markVisible(mPager.getCurrentItem());
        }
        requestLayout();
    }

    private void onAdClicked(String id) {
        String clickUrl = BrowtherAdsBridge.getClickUrl(id);
        if (clickUrl != null && !clickUrl.isEmpty()) {
            // L'API log le click puis 302 vers la destination (parité desktop
            // OpenGURL NEW_FOREGROUND_TAB + iOS onAdTapped nouvel onglet).
            TabUtils.openUrlInNewTab(/* isIncognito= */ false, clickUrl);
        }
    }

    private void markVisible(int position) {
        if (position < 0 || position >= mAds.length) {
            return;
        }
        String id = mAds[position].id;
        if (!mMarkedVisible.add(id)) {
            return; // déjà compté dans cette instance
        }
        BrowtherAdsBridge.markVisible(id);
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        mAttached = true;
        // La bannière entre dans le viewport (RecyclerView attache la vue) →
        // impression de la page courante.
        if (mPager != null && mAds.length > 0) {
            markVisible(mPager.getCurrentItem());
        }
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        mAttached = false;
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        // Hauteur du pager = largeur / ratio (champ `ratio` du serve, largeur
        // fluide). Calée AVANT de mesurer les enfants (plus déterministe
        // qu'onSizeChanged qui dépend d'un 2e passage de layout dans une
        // RecyclerView).
        int width = MeasureSpec.getSize(widthMeasureSpec);
        int pagerWidth = width - getPaddingLeft() - getPaddingRight();
        // + headroom pour l'onglet label : l'image (page moins son paddingTop)
        // garde `pagerWidth / ratio`, le pager est juste plus haut d'autant.
        int targetHeight = Math.round(pagerWidth / mAdRatio)
                + ViewUtils.dpToPx(getContext(), LABEL_HEADROOM_DP);
        if (mPager != null && targetHeight > 0 && targetHeight != mPagerHeight) {
            mPagerHeight = targetHeight;
            ViewGroup.LayoutParams lp = mPager.getLayoutParams();
            lp.height = targetHeight;
            mPager.setLayoutParams(lp);
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec);
    }

    /** "3.2:1" → 3.2f ; fallback si champ absent/illisible (vieux cache serveur). */
    private static float parseRatio(@Nullable String ratio) {
        if (ratio == null || ratio.isEmpty()) {
            return FALLBACK_AD_RATIO;
        }
        int sep = ratio.indexOf(':');
        if (sep <= 0 || sep >= ratio.length() - 1) {
            return FALLBACK_AD_RATIO;
        }
        try {
            float w = Float.parseFloat(ratio.substring(0, sep));
            float h = Float.parseFloat(ratio.substring(sep + 1));
            if (w > 0 && h > 0) {
                return w / h;
            }
        } catch (NumberFormatException e) {
            // fallback ci-dessous
        }
        return FALLBACK_AD_RATIO;
    }

    private void buildDots(int count) {
        mDots.removeAllViews();
        if (count <= 1) {
            mDots.setVisibility(View.GONE);
            return;
        }
        mDots.setVisibility(View.VISIBLE);
        int size = ViewUtils.dpToPx(getContext(), 6);
        int margin = ViewUtils.dpToPx(getContext(), 3);
        for (int i = 0; i < count; i++) {
            View dot = new View(getContext());
            GradientDrawable bg = new GradientDrawable();
            bg.setShape(GradientDrawable.OVAL);
            bg.setColor(Color.WHITE);
            dot.setBackground(bg);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(size, size);
            lp.setMargins(margin, 0, margin, 0);
            dot.setLayoutParams(lp);
            mDots.addView(dot);
        }
    }

    private void updateDots(int selected) {
        for (int i = 0; i < mDots.getChildCount(); i++) {
            mDots.getChildAt(i).setAlpha(i == selected ? 1f : 0.4f);
        }
    }
}
