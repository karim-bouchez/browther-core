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

import org.chromium.base.Log;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_ads.BrowtherAdsBridge;
import org.chromium.chrome.browser.util.TabUtils;
import org.chromium.ui.base.ViewUtils;

import java.util.HashSet;
import java.util.Set;

/**
 * Bannière pub devndin-ads sous les favoris du NTP. Carousel paginé ratio 3.2:1
 * (parité desktop {@code browther_ad_banner.tsx} + iOS {@code BrowtheAdSectionProvider}).
 *
 * <p>Le serve signé HMAC, le batching des impressions et la résolution du click
 * URL vivent dans {@link BrowtherAdsBridge} (client C++) — le secret publisher
 * ne touche jamais cette vue. Seuls {@code id} + {@code imageUrl} arrivent ici.
 *
 * <p>Impression à visibilité réelle (parité IntersectionObserver desktop / iOS
 * {@code didMarkInitial}) : on ne signale une page que lorsque la bannière est
 * réellement attachée au viewport ({@link #onAttachedToWindow()}) et à chaque
 * settle de page ({@code onPageSelected}). Idempotent par {@code id} (Set local
 * + déduplication côté client C++).
 */
public class BrowtherAdBannerView extends LinearLayout {
    // Ratio image 3.2:1 (V1, parité ads/docs/INTEGRATION.md § 3).
    private static final float AD_RATIO = 3.2f;

    private ViewPager2 mPager;
    private LinearLayout mDots;
    private BrowtherAdsBridge.Ad[] mAds = new BrowtherAdsBridge.Ad[0];
    // Pubs déjà signalées visibles dans cette instance (le client C++ dédup aussi).
    private final Set<String> mMarkedVisible = new HashSet<>();
    private boolean mAttached;
    private int mPagerHeight;

    public BrowtherAdBannerView(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
    }

    @Override
    protected void onFinishInflate() {
        super.onFinishInflate();
        mPager = findViewById(R.id.browther_ad_pager);
        mDots = findViewById(R.id.browther_ad_dots);
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
        Log.i("BrowtherAds", "BannerView.setAds: n=" + mAds.length
                + " width=" + getWidth() + " pagerH=" + mPagerHeight);
        mMarkedVisible.clear();
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
        // Hauteur du pager = largeur / 3.2 (ratio image fixe, largeur fluide).
        // Calée AVANT de mesurer les enfants (plus déterministe qu'onSizeChanged
        // qui dépend d'un 2e passage de layout dans une RecyclerView).
        int width = MeasureSpec.getSize(widthMeasureSpec);
        int pagerWidth = width - getPaddingLeft() - getPaddingRight();
        int targetHeight = Math.round(pagerWidth / AD_RATIO);
        if (mPager != null && targetHeight > 0 && targetHeight != mPagerHeight) {
            mPagerHeight = targetHeight;
            ViewGroup.LayoutParams lp = mPager.getLayoutParams();
            lp.height = targetHeight;
            mPager.setLayoutParams(lp);
            Log.i("BrowtherAds", "BannerView.onMeasure: width=" + width
                    + " → pagerHeight=" + targetHeight);
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec);
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
