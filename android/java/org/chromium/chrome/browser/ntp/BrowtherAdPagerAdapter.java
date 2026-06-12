/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.ntp;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import com.bumptech.glide.RequestManager;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.app.helpers.ImageLoader;
import org.chromium.chrome.browser.browther_ads.BrowtherAdsBridge;

/**
 * Adapter du carousel ViewPager2 de la bannière pub devndin-ads : une pub
 * pleine largeur par page (parité desktop scroll-snap + iOS carousel paginé).
 */
class BrowtherAdPagerAdapter extends RecyclerView.Adapter<BrowtherAdPagerAdapter.AdViewHolder> {
    // Coins arrondis de l'image (parité iOS BrowtheAdImageCell cornerRadius 16).
    private static final int CORNER_RADIUS_DP = 16;

    interface OnAdClickListener {
        void onAdClick(String id);
    }

    private final BrowtherAdsBridge.Ad[] mAds;
    private final RequestManager mGlide;
    private final OnAdClickListener mClickListener;

    BrowtherAdPagerAdapter(
            BrowtherAdsBridge.Ad[] ads, RequestManager glide, OnAdClickListener clickListener) {
        mAds = ads;
        mGlide = glide;
        mClickListener = clickListener;
    }

    @NonNull
    @Override
    public AdViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view =
                LayoutInflater.from(parent.getContext())
                        .inflate(R.layout.browther_ad_banner_item, parent, false);
        return new AdViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull AdViewHolder holder, int position) {
        BrowtherAdsBridge.Ad ad = mAds[position];
        // Image distante chargée via la stack réseau Chromium (ImageFetcher
        // NETWORK_ONLY) + coins arrondis Glide — pas de second client HTTP Java.
        ImageLoader.downloadImage(
                ad.imageUrl,
                mGlide,
                /* isCircular= */ false,
                CORNER_RADIUS_DP,
                holder.mImageView,
                /* callback= */ null);
        // Click → l'API log puis 302 vers la destination (résolu par le client C++).
        holder.itemView.setOnClickListener(view -> mClickListener.onAdClick(ad.id));
    }

    @Override
    public int getItemCount() {
        return mAds.length;
    }

    static class AdViewHolder extends RecyclerView.ViewHolder {
        final ImageView mImageView;

        AdViewHolder(@NonNull View itemView) {
            super(itemView);
            mImageView = (ImageView) itemView.findViewById(R.id.browther_ad_image);
        }
    }
}
