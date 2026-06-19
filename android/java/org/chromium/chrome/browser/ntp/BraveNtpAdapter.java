/* Copyright (c) 2022 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.ntp;

import static org.chromium.ui.base.ViewUtils.dpToPx;

import android.app.Activity;
import android.graphics.Bitmap;
import android.text.Spannable;
import android.text.SpannableStringBuilder;
import android.util.Pair;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import com.bumptech.glide.RequestManager;

import org.chromium.base.Log;
import org.chromium.base.task.PostTask;
import org.chromium.base.task.TaskTraits;
import org.chromium.brave_news.mojom.BraveNewsController;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.app.BraveActivity;
import org.chromium.chrome.browser.brave_news.CardBuilderFeedCard;
import org.chromium.chrome.browser.brave_news.models.FeedItemsCard;
import org.chromium.chrome.browser.brave_stats.BraveStatsUtil;
import org.chromium.chrome.browser.browther_ads.BrowtherAdsBridge;
import org.chromium.chrome.browser.browther_analytics.BrowtherAnalyticsBridge;
import org.chromium.chrome.browser.ntp_background_images.NTPBackgroundImagesBridge;
import org.chromium.chrome.browser.ntp_background_images.model.BackgroundImage;
import org.chromium.chrome.browser.ntp_background_images.model.NTPImage;
import org.chromium.chrome.browser.ntp_background_images.model.SponsoredTab;
import org.chromium.chrome.browser.ntp_background_images.model.Wallpaper;
import org.chromium.chrome.browser.ntp_background_images.util.NTPImageUtil;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.preferences.ChromeSharedPreferences;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.chrome.browser.settings.BackgroundImagesPreferences;
import org.chromium.chrome.browser.util.BraveConstants;
import org.chromium.chrome.browser.util.BraveTouchUtils;
import org.chromium.chrome.browser.util.TabUtils;
import org.chromium.components.user_prefs.UserPrefs;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

public class BraveNtpAdapter extends RecyclerView.Adapter<RecyclerView.ViewHolder> {
    private final Activity mActivity;
    private final RequestManager mGlide;
    private BraveNewsController mBraveNewsController;
    private final View mMvTilesContainerLayout;
    private final CopyOnWriteArrayList<FeedItemsCard> mNewsItems;
    private NTPImage mNtpImage;
    private final SponsoredTab mSponsoredTab;
    private Bitmap mSponsoredLogo;
    private Wallpaper mWallpaper;
    private final NTPBackgroundImagesBridge mNTPBackgroundImagesBridge;
    private final OnBraveNtpListener mOnBraveNtpListener;
    private boolean mIsDisplayNewsFeed;
    private boolean mIsDisplayNewsOptin;
    private boolean mIsNewsLoading;
    private boolean mIsNewContent;
    private boolean mIsNewContentLoading;
    private boolean mIsTopSitesEnabled;
    private boolean mIsBraveStatsEnabled;
    // Browther : bannière pub devndin-ads (sous les favoris). Vide tant que le
    // serve async n'a rien renvoyé → getAdsCount() == 0 → pas d'item.
    private BrowtherAdsBridge.Ad[] mAds = new BrowtherAdsBridge.Ad[0];
    private int mRecyclerViewHeight;
    private int mStatsHeight;
    private int mTopSitesHeight;
    private int mNewContentHeight;
    private int mTopMarginImageCredit;
    private float mImageCreditAlpha = 1f;

    private static final int TYPE_STATS = 1;
    private static final int TYPE_TOP_SITES = 2;
    private static final int TYPE_NEW_CONTENT = 3;
    private static final int TYPE_IMAGE_CREDIT = 4;
    private static final int TYPE_NEWS_OPTIN = 5;
    private static final int TYPE_NEWS_LOADING = 6;
    private static final int TYPE_NEWS = 7;
    private static final int TYPE_NEWS_NO_CONTENT_SOURCES = 8;
    // Browther : bannière pub devndin-ads, insérée entre les stats et les
    // favoris (mobile : au-dessus des favoris, parité iOS).
    private static final int TYPE_BROWTHER_ADS = 9;

    private static final int ONE_ITEM_SPACE = 1;
    private static final int TWO_ITEMS_SPACE = 2;
    private static final String TAG = "BraveNtpAdapter";

    public BraveNtpAdapter(Activity activity, OnBraveNtpListener onBraveNtpListener,
            RequestManager glide, CopyOnWriteArrayList<FeedItemsCard> newsItems,
            BraveNewsController braveNewsController, View mvTilesContainerLayout, NTPImage ntpImage,
            SponsoredTab sponsoredTab, Wallpaper wallpaper, Bitmap sponsoredLogo,
            NTPBackgroundImagesBridge nTPBackgroundImagesBridge, boolean isNewsLoading,
            int recyclerViewHeight, boolean isTopSitesEnabled, boolean isBraveStatsEnabled,
            boolean isDisplayNewsFeed, boolean isDisplayNewsOptin) {
        mActivity = activity;
        mOnBraveNtpListener = onBraveNtpListener;
        mGlide = glide;
        mNewsItems = newsItems;
        mBraveNewsController = braveNewsController;
        mMvTilesContainerLayout = mvTilesContainerLayout;
        mNtpImage = ntpImage;
        mSponsoredTab = sponsoredTab;
        mWallpaper = wallpaper;
        mSponsoredLogo = sponsoredLogo;
        mNTPBackgroundImagesBridge = nTPBackgroundImagesBridge;
        mIsNewsLoading = isNewsLoading;
        mRecyclerViewHeight = recyclerViewHeight;
        mIsTopSitesEnabled = isTopSitesEnabled;
        mIsBraveStatsEnabled = isBraveStatsEnabled;
        mIsDisplayNewsFeed = isDisplayNewsFeed;
        mIsDisplayNewsOptin = isDisplayNewsOptin;
    }

    @Override
    public void onBindViewHolder(@NonNull RecyclerView.ViewHolder holder, int position) {
        if (holder instanceof StatsViewHolder) {
            StatsViewHolder statsViewHolder = (StatsViewHolder) holder;

            // Browther : stats Browther (musique / personnes / trackers) à la
            // place de (trackers / data / time). Mapping des ids XML conservé
            // pour minimiser le diff :
            //   col1 (ex-ads_count)  → musique retirée (Sawtunaa)
            //   col2 (ex-data_saved) → personnes floutées (Basarunaa)
            //   col3 (ex-time_count) → trackers & ads bloqués (Shields)
            Pair<String, String> musicPair =
                    BraveStatsUtil.getBraveStatsStringFromTime(
                            BrowtherAnalyticsBridge.getMusicSecondsTotal());
            long personsBlurred = BrowtherAnalyticsBridge.getPersonsBlurredTotal();
            Pair<String, String> adsTrackersPair = BraveStatsUtil.getAdsTrackersBlocked();

            statsViewHolder.mAdsBlockedCountTv.setText(musicPair.first);
            statsViewHolder.mAdsBlockedCountTextTv.setText(musicPair.second);
            statsViewHolder.mDataSavedValueTv.setText(String.valueOf(personsBlurred));
            statsViewHolder.mDataSavedValueTextTv.setText("");
            statsViewHolder.mEstTimeSavedCountTv.setText(adsTrackersPair.first);
            statsViewHolder.mEstTimeSavedCountTextTv.setText(adsTrackersPair.second);

            LinearLayout.LayoutParams layoutParams =
                    new LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.MATCH_PARENT,
                            LinearLayout.LayoutParams.WRAP_CONTENT);
            int margin = dpToPx(mActivity, 16);
            layoutParams.setMargins(margin, margin, margin, 0);
            statsViewHolder.mNtpStatsLayout.setLayoutParams(layoutParams);
            statsViewHolder.mNtpStatsLayout.setOnClickListener(
                    view -> {
                        mOnBraveNtpListener.checkForBraveStats();
                    });

            mStatsHeight = NTPImageUtil.getViewHeight(statsViewHolder.itemView) + margin;

        } else if (holder instanceof AdsViewHolder) {
            AdsViewHolder adsViewHolder = (AdsViewHolder) holder;

            LinearLayout.LayoutParams layoutParams =
                    new LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.MATCH_PARENT,
                            LinearLayout.LayoutParams.WRAP_CONTENT);
            int margin = dpToPx(mActivity, 16);
            layoutParams.setMargins(margin, margin, margin, 0);
            adsViewHolder.mBannerView.setLayoutParams(layoutParams);

            // La vue gère elle-même serve→affichage, impressions à visibilité
            // réelle et click (parité iOS BrowtheAdSectionProvider).
            adsViewHolder.mBannerView.setAds(mAds, mGlide);

        } else if (holder instanceof TopSitesViewHolder) {
            LinearLayout.LayoutParams layoutParams =
                    new LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.MATCH_PARENT,
                            LinearLayout.LayoutParams.WRAP_CONTENT);
            int margin = dpToPx(mActivity, 16);
            layoutParams.setMargins(margin, margin, margin, 0);

            mMvTilesContainerLayout.setLayoutParams(layoutParams);
            mMvTilesContainerLayout.setBackgroundResource(R.drawable.rounded_dark_bg_alpha);
            mTopSitesHeight = NTPImageUtil.getViewHeight(holder.itemView) + margin;

        } else if (holder instanceof NewContentViewHolder) {
            NewContentViewHolder newContentViewHolder = (NewContentViewHolder) holder;

            newContentViewHolder.mNewContentLayout.setOnClickListener(
                    view -> {
                        mOnBraveNtpListener.loadNewContent();
                    });

            if (mIsNewContentLoading) {
                newContentViewHolder.mNewContentLayout.setClickable(false);
                newContentViewHolder.mNewContentText.setVisibility(View.GONE);
                newContentViewHolder.mNewContentProgressBar.setVisibility(View.VISIBLE);
            } else {
                newContentViewHolder.mNewContentLayout.setClickable(true);
                newContentViewHolder.mNewContentText.setVisibility(View.VISIBLE);
                newContentViewHolder.mNewContentProgressBar.setVisibility(View.GONE);
            }
            mNewContentHeight =
                    NTPImageUtil.getViewHeight(newContentViewHolder.itemView)
                            + dpToPx(mActivity, 10);

        } else if (holder instanceof ImageCreditViewHolder) {
            ImageCreditViewHolder imageCreditViewHolder = (ImageCreditViewHolder) holder;

            if (UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                            .getBoolean(BravePref.NEW_TAB_PAGE_SHOW_BACKGROUND_IMAGE)
                    && mSponsoredTab != null
                    && NTPImageUtil.shouldEnableNTPFeature()) {
                if (mNtpImage instanceof BackgroundImage) {
                    // Browther: tag "Photo de [Auteur]" caché — les 10 paysages
                    // islamiques NTP sont libres de droit (Unsplash + photos
                    // Browther), pas d'attribution nécessaire. Le mCreditTv
                    // upstream affichait R.string.photo_by qui crée du visuel
                    // sans valeur ajoutée user.
                    imageCreditViewHolder.mSponsoredLogo.setVisibility(View.GONE);
                    imageCreditViewHolder.mCreditTv.setVisibility(View.GONE);
                }
            }
            if (mSponsoredLogo != null) {
                imageCreditViewHolder.mSponsoredLogo.setVisibility(View.VISIBLE);
                imageCreditViewHolder.mSponsoredLogo.setImageBitmap(mSponsoredLogo);
                imageCreditViewHolder.mSponsoredLogo.setOnClickListener(
                        view -> {
                            if (mWallpaper.getLogoDestinationUrl() != null) {
                                TabUtils.openUrlInSameTab(mWallpaper.getLogoDestinationUrl());
                                mNTPBackgroundImagesBridge.wallpaperLogoClicked(mWallpaper);
                            }
                        });
            }

            if (mRecyclerViewHeight > 0) {
                LinearLayout.LayoutParams layoutParams =
                        new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT,
                                LinearLayout.LayoutParams.WRAP_CONTENT);

                int extraMarginForNews =
                        (mIsDisplayNewsOptin || shouldDisplayNewsLoading() || mIsDisplayNewsFeed)
                                ? dpToPx(mActivity, 30)
                                : 0;

                mTopMarginImageCredit =
                        mRecyclerViewHeight
                                - NTPImageUtil.getViewHeight(imageCreditViewHolder.itemView)
                                - extraMarginForNews;

                if (isStatsEnabled()) {
                    mTopMarginImageCredit -= mStatsHeight;
                } else {
                    mTopMarginImageCredit -= dpToPx(mActivity, 16);
                }

                if (mIsTopSitesEnabled) {
                    mTopMarginImageCredit -= mTopSitesHeight;
                }

                if (mIsNewContent) {
                    mTopMarginImageCredit -= mNewContentHeight;
                }

                if (mTopMarginImageCredit < 0) {
                    mTopMarginImageCredit = 0;
                }

                layoutParams.setMargins(0, mTopMarginImageCredit, 0, 0);

                imageCreditViewHolder.mNtpImageCreditLayout.setLayoutParams(layoutParams);
            }
            imageCreditViewHolder.mImageCreditLayout.setAlpha(mImageCreditAlpha);

        } else if (holder instanceof NewsOptinViewHolder) {
            NewsOptinViewHolder newsOptinViewHolder = (NewsOptinViewHolder) holder;

            LinearLayout.LayoutParams layoutParams = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            int margin = dpToPx(mActivity, 30);
            layoutParams.setMargins(margin, 0, margin, margin);

            newsOptinViewHolder.itemView.setLayoutParams(layoutParams);

            newsOptinViewHolder.mOptinClose.setOnClickListener(
                    view -> {
                        mOnBraveNtpListener.updateNewsOptin(false);
                    });

            newsOptinViewHolder.mOptinLearnMore.setOnClickListener(
                    view -> {
                        TabUtils.openUrlInSameTab(BraveConstants.BRAVE_NEWS_LEARN_MORE_URL);
                    });

            newsOptinViewHolder.mOptinButton.setOnClickListener(
                    view -> {
                        mOnBraveNtpListener.updateNewsOptin(true);
                        mOnBraveNtpListener.getFeed(false);
                    });

        } else if (holder instanceof NewsViewHolder) {
            NewsViewHolder newsViewHolder = (NewsViewHolder) holder;
            newsViewHolder.mLinearLayout.removeAllViews();

            int newsLoadingCount = shouldDisplayNewsLoading() ? 1 : 0;
            int newsPosition =
                    position
                            - getStatsCount()
                            - getTopSitesCount()
                            - getAdsCount()
                            - ONE_ITEM_SPACE
                            - getNewContentCount()
                            - newsLoadingCount;
            if (newsPosition < mNewsItems.size() && newsPosition >= 0) {
                FeedItemsCard newsItem = mNewsItems.get(newsPosition);
                if (mBraveNewsController != null) {
                    new CardBuilderFeedCard(
                            mBraveNewsController,
                            mGlide,
                            newsViewHolder.mLinearLayout,
                            mActivity,
                            newsPosition,
                            newsItem,
                            newsItem.getCardType());
                }
            }
        } else if (holder instanceof NoSourcesViewHolder) {
            NoSourcesViewHolder noSourcesViewHolder = (NoSourcesViewHolder) holder;

            LinearLayout.LayoutParams layoutParams = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            int margin = dpToPx(mActivity, 30);
            layoutParams.setMargins(margin, 0, margin, margin);

            noSourcesViewHolder.itemView.setLayoutParams(layoutParams);

            noSourcesViewHolder.mBtnChooseContent.setOnClickListener(
                    view -> {
                        if (mActivity instanceof BraveActivity) {
                            ((BraveActivity) mActivity).openBraveNewsSettings();
                        }
                    });
        }
    }

    @Override
    public int getItemCount() {
        int statsCount = getStatsCount();
        int topSitesCount = getTopSitesCount();
        int adsCount = getAdsCount();
        int newsLoadingCount = shouldDisplayNewsLoading() ? 1 : 0;
        if (mIsDisplayNewsOptin) {
            return statsCount + topSitesCount + adsCount + TWO_ITEMS_SPACE + newsLoadingCount;
        } else if (mIsDisplayNewsFeed) {
            int newsCount = 0;
            if (mNewsItems.size() > 0) {
                newsCount = mNewsItems.size();
            } else if (newsLoadingCount == 0) {
                newsCount = 1;
            }
            return statsCount + topSitesCount + adsCount + ONE_ITEM_SPACE + getNewContentCount()
                    + newsLoadingCount + newsCount;
        } else {
            return statsCount + topSitesCount + adsCount + ONE_ITEM_SPACE + newsLoadingCount;
        }
    }

    @NonNull
    @Override
    public RecyclerView.ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
        View view;
        if (viewType == TYPE_STATS) {
            view = LayoutInflater.from(parent.getContext())
                           .inflate(R.layout.brave_stats_layout, parent, false);
            return new StatsViewHolder(view);

        } else if (viewType == TYPE_BROWTHER_ADS) {
            view = LayoutInflater.from(parent.getContext())
                           .inflate(R.layout.browther_ad_banner, parent, false);
            return new AdsViewHolder(view);

        } else if (viewType == TYPE_TOP_SITES) {
            return new TopSitesViewHolder(mMvTilesContainerLayout);

        } else if (viewType == TYPE_NEW_CONTENT) {
            view = LayoutInflater.from(parent.getContext())
                           .inflate(R.layout.brave_news_load_new_content, parent, false);
            return new NewContentViewHolder(view);

        } else if (viewType == TYPE_IMAGE_CREDIT) {
            view = LayoutInflater.from(parent.getContext())
                           .inflate(R.layout.ntp_image_credit, parent, false);
            return new ImageCreditViewHolder(view);

        } else if (viewType == TYPE_NEWS_OPTIN) {
            view = LayoutInflater.from(parent.getContext())
                           .inflate(R.layout.optin_layout, parent, false);
            return new NewsOptinViewHolder(view);

        } else if (viewType == TYPE_NEWS_LOADING) {
            view = LayoutInflater.from(parent.getContext())
                           .inflate(R.layout.news_loading, parent, false);
            return new NewsLoadingViewHolder(view);

        } else if (viewType == TYPE_NEWS_NO_CONTENT_SOURCES) {
            view = LayoutInflater.from(parent.getContext())
                           .inflate(R.layout.brave_news_no_sources, parent, false);
            return new NoSourcesViewHolder(view);

        } else {
            view = LayoutInflater.from(parent.getContext())
                           .inflate(R.layout.brave_news_row, parent, false);
            return new NewsViewHolder(view);
        }
    }

    @Override
    public int getItemViewType(int position) {
        int statsCount = getStatsCount();
        int topSitesCount = getTopSitesCount();
        int adsCount = getAdsCount();
        // Base des items en aval (new content / image credit / news) : décalée
        // par la bannière pub. La somme stats+ads+topsites est invariante quel
        // que soit l'ordre relatif ads/topsites → la base reste identique.
        int base = statsCount + topSitesCount + adsCount;

        // Ordre mobile (parité iOS) : Stats → Pub → Favoris → ...
        if (position == 0 && statsCount == 1) {
            return TYPE_STATS;
        } else if (adsCount == 1 && position == statsCount) {
            return TYPE_BROWTHER_ADS;
        } else if (topSitesCount == 1 && position == statsCount + adsCount) {
            return TYPE_TOP_SITES;
        } else if (position == base && mIsNewContent) {
            return TYPE_NEW_CONTENT;
        } else if ((position == base && !mIsNewContent)
                || (position == base + ONE_ITEM_SPACE && mIsNewContent)) {
            return TYPE_IMAGE_CREDIT;
        } else if (position == base + ONE_ITEM_SPACE
                && mIsDisplayNewsOptin
                && !mIsNewContent) {
            return TYPE_NEWS_OPTIN;
        } else if (position == base + ONE_ITEM_SPACE
                && shouldDisplayNewsLoading()
                && !mIsNewContent) {
            return TYPE_NEWS_LOADING;
        } else if (!shouldDisplayNewsLoading() && mNewsItems.size() == 0) {
            return TYPE_NEWS_NO_CONTENT_SOURCES;
        } else {
            return TYPE_NEWS;
        }
    }

    public int getStatsCount() {
        return isStatsEnabled() ? 1 : 0;
    }

    // Will be used in privacy hub feature
    private boolean isStatsEnabled() {
        return mIsBraveStatsEnabled;
    }

    public int getTopSitesCount() {
        return mIsTopSitesEnabled ? 1 : 0;
    }

    public int getAdsCount() {
        return mAds.length > 0 ? 1 : 0;
    }

    /**
     * Renseigne les pubs servies (serve async terminé). Insère / met à jour la
     * bannière entre les stats et les favoris (position {@code statsCount},
     * parité iOS mobile — au-dessus des favoris).
     */
    public void setAds(BrowtherAdsBridge.Ad[] ads) {
        boolean had = getAdsCount() == 1;
        mAds = ads != null ? ads : new BrowtherAdsBridge.Ad[0];
        boolean has = getAdsCount() == 1;
        int position = getStatsCount();
        if (has && !had) {
            notifyItemInserted(position);
        } else if (!has && had) {
            notifyItemRemoved(position);
        } else if (has) {
            notifyItemChanged(position);
        }
    }

    public void setTopSitesEnabled(boolean isTopSitesEnabled) {
        if (mIsTopSitesEnabled != isTopSitesEnabled) {
            mIsTopSitesEnabled = isTopSitesEnabled;
            // Les top sites sont maintenant après la pub (Stats → Pub → Favoris).
            if (mIsTopSitesEnabled) {
                notifyItemInserted(getStatsCount() + getAdsCount());
            } else {
                notifyItemRemoved(getStatsCount() + getAdsCount());
            }
            notifyItemRangeChanged(getStatsCount(),
                    getStatsCount() + getTopSitesCount() + getAdsCount() + getNewContentCount()
                            + ONE_ITEM_SPACE);
        }
    }

    public void setBraveStatsEnabled(boolean isBraveStatsEnabled) {
        if (mIsBraveStatsEnabled != isBraveStatsEnabled) {
            mIsBraveStatsEnabled = isBraveStatsEnabled;
            if (mIsBraveStatsEnabled) {
                notifyItemInserted(getStatsCount());
            } else {
                notifyItemRemoved(getStatsCount());
            }
        }
    }

    public void setDisplayNewsFeed(boolean isDisplayNewsFeed) {
        if (mIsDisplayNewsFeed != isDisplayNewsFeed) {
            mIsDisplayNewsFeed = isDisplayNewsFeed;
            if (mIsDisplayNewsFeed) {
                notifyItemRangeChanged(
                        getStatsCount() + getTopSitesCount() + getAdsCount(), TWO_ITEMS_SPACE);
            } else {
                notifyItemRangeRemoved(
                        getStatsCount() + getTopSitesCount() + getAdsCount() + ONE_ITEM_SPACE,
                        mNewsItems.size());
            }
        }
    }

    public void removeNewsOptin() {
        mIsDisplayNewsOptin = false;
        notifyItemRemoved(getStatsCount() + getTopSitesCount() + getAdsCount() + ONE_ITEM_SPACE);
    }

    public boolean shouldDisplayNewsLoading() {
        return mIsNewsLoading && mIsDisplayNewsFeed;
    }

    public int getTopMarginImageCredit() {
        return mTopMarginImageCredit;
    }

    public void setNewsLoading(boolean isNewsLoading) {
        mIsNewsLoading = isNewsLoading;
        if (isNewsLoading) {
            notifyItemInserted(getStatsCount() + getTopSitesCount() + getAdsCount() + ONE_ITEM_SPACE);
        } else {
            notifyItemRemoved(getStatsCount() + getTopSitesCount() + getAdsCount() + ONE_ITEM_SPACE);
        }
        notifyItemRangeChanged(
                getStatsCount() + getTopSitesCount() + getAdsCount(), TWO_ITEMS_SPACE);
    }

    public void setNewContent(boolean isNewContent) {
        if (mIsNewContent != isNewContent) {
            mIsNewContent = isNewContent;
            int newContentPosition = getStatsCount() + getTopSitesCount() + getAdsCount();
            if (!isNewContent) {
                mIsNewContentLoading = false;
                notifyItemRemoved(newContentPosition);
            } else {
                notifyItemInserted(newContentPosition);
            }

            notifyItemRangeChanged(newContentPosition, TWO_ITEMS_SPACE);
        }
    }

    public boolean isNewContent() {
        return mIsNewContent;
    }

    public void setNewContentLoading(boolean isNewContentLoading) {
        mIsNewContentLoading = isNewContentLoading;
        notifyItemChanged(getStatsCount() + getTopSitesCount() + getAdsCount());
    }

    public int getNewContentCount() {
        return mIsNewContent ? 1 : 0;
    }

    public void setSponsoredLogo(Wallpaper wallpaper, Bitmap sponsoredLogo) {
        mWallpaper = wallpaper;
        mSponsoredLogo = sponsoredLogo;
        notifyItemChanged(
                getStatsCount() + getTopSitesCount() + getAdsCount() + getNewContentCount());
    }

    public void setNtpImage(NTPImage ntpImage) {
        mNtpImage = ntpImage;
        notifyItemChanged(
                getStatsCount() + getTopSitesCount() + getAdsCount() + getNewContentCount());
    }

    public void setBraveNewsController(BraveNewsController braveNewsController) {
        mBraveNewsController = braveNewsController;
        notifyItemChanged(getStatsCount() + getTopSitesCount() + getAdsCount()
                + getNewContentCount() + ONE_ITEM_SPACE);
    }

    public void setImageCreditAlpha(float alpha) {
        if (mImageCreditAlpha == alpha) {
            return;
        }
        // We have to use PostTask otherwise it's possible to get IllegalStateException
        // during a call to notifyItemChanged when scrolling is in progress, see details
        // here https://github.com/brave/brave-browser/issues/29343
        PostTask.postTask(TaskTraits.UI_DEFAULT, () -> {
            mImageCreditAlpha = alpha;
            try {
                notifyItemChanged(
                        getStatsCount() + getTopSitesCount() + getAdsCount() + getNewContentCount());
            } catch (IllegalStateException e) {
                Log.e(TAG, "setImageCreditAlpha: " + e.getMessage());
            }
        });
    }

    public void setRecyclerViewHeight(int recyclerViewHeight) {
        mRecyclerViewHeight = recyclerViewHeight;
        int count = getStatsCount() + getTopSitesCount() + getAdsCount() + getNewContentCount()
                + ONE_ITEM_SPACE;
        if (getItemCount() > count) {
            count += 1;
        }
        notifyItemRangeChanged(0, count);
    }

    public static class StatsViewHolder extends RecyclerView.ViewHolder {
        LinearLayout mNtpStatsLayout;
        LinearLayout mTitleLayout;
        // Browther : mHideStatsImg retiré, le bouton "hide stats card" n'existe
        // plus dans brave_stats_layout.xml — widget toujours visible.
        TextView mAdsBlockedCountTv;
        TextView mAdsBlockedCountTextTv;
        TextView mDataSavedValueTv;
        TextView mDataSavedValueTextTv;
        TextView mEstTimeSavedCountTv;
        TextView mEstTimeSavedCountTextTv;

        StatsViewHolder(View itemView) {
            super(itemView);
            this.mNtpStatsLayout = (LinearLayout) itemView.findViewById(R.id.ntp_stats_layout);
            this.mTitleLayout = (LinearLayout) itemView.findViewById(R.id.brave_stats_title_layout);
            this.mAdsBlockedCountTv =
                    (TextView) itemView.findViewById(R.id.brave_stats_text_ads_count);
            this.mAdsBlockedCountTextTv =
                    (TextView) itemView.findViewById(R.id.brave_stats_text_ads_count_text);
            this.mDataSavedValueTv =
                    (TextView) itemView.findViewById(R.id.brave_stats_data_saved_value);
            this.mDataSavedValueTextTv =
                    (TextView) itemView.findViewById(R.id.brave_stats_data_saved_value_text);
            this.mEstTimeSavedCountTv =
                    (TextView) itemView.findViewById(R.id.brave_stats_text_time_count);
            this.mEstTimeSavedCountTextTv =
                    (TextView) itemView.findViewById(R.id.brave_stats_text_time_count_text);
        }
    }

    public static class TopSitesViewHolder extends RecyclerView.ViewHolder {
        TopSitesViewHolder(View itemView) {
            super(itemView);
        }
    }

    public static class AdsViewHolder extends RecyclerView.ViewHolder {
        final BrowtherAdBannerView mBannerView;

        AdsViewHolder(View itemView) {
            super(itemView);
            this.mBannerView = (BrowtherAdBannerView) itemView;
        }
    }

    public static class NewContentViewHolder extends RecyclerView.ViewHolder {
        LinearLayout mNewContentLayout;
        TextView mNewContentText;
        ProgressBar mNewContentProgressBar;

        NewContentViewHolder(View itemView) {
            super(itemView);
            this.mNewContentLayout = (LinearLayout) itemView.findViewById(R.id.new_content_layout);
            this.mNewContentProgressBar =
                    (ProgressBar) itemView.findViewById(R.id.new_content_loading_spinner);
            this.mNewContentText = (TextView) itemView.findViewById(R.id.new_content_button_text);
        }
    }

    public static class ImageCreditViewHolder extends RecyclerView.ViewHolder {
        LinearLayout mNtpImageCreditLayout;
        FrameLayout mImageCreditLayout;
        TextView mCreditTv;
        ImageView mSponsoredLogo;

        ImageCreditViewHolder(View itemView) {
            super(itemView);
            this.mNtpImageCreditLayout =
                    (LinearLayout) itemView.findViewById(R.id.ntp_image_credit_layout);
            this.mImageCreditLayout = (FrameLayout) itemView.findViewById(R.id.image_credit_layout);
            this.mCreditTv = (TextView) itemView.findViewById(R.id.credit_text);
            this.mSponsoredLogo = (ImageView) itemView.findViewById(R.id.sponsored_logo);
            BraveTouchUtils.ensureMinTouchTarget(this.mCreditTv);
        }
    }

    public static class NewsOptinViewHolder extends RecyclerView.ViewHolder {
        FrameLayout mOptinButton;
        ProgressBar mOptinLoadingSpinner;
        ImageView mOptinClose;
        TextView mOptinLearnMore;
        TextView mOptinTv;

        NewsOptinViewHolder(View itemView) {
            super(itemView);
            mOptinButton = (FrameLayout) itemView.findViewById(R.id.optin_button);
            mOptinClose = (ImageView) itemView.findViewById(R.id.close_optin);
            mOptinLearnMore = (TextView) itemView.findViewById(R.id.optin_learnmore);
            mOptinTv = (TextView) itemView.findViewById(R.id.optin_button_text);
            mOptinLoadingSpinner = (ProgressBar) itemView.findViewById(R.id.optin_loading_spinner);
            BraveTouchUtils.ensureMinTouchTarget(mOptinButton);
            BraveTouchUtils.ensureMinTouchTarget(mOptinLearnMore);
        }
    }

    public static class NewsLoadingViewHolder extends RecyclerView.ViewHolder {
        LinearLayout mLinearLayout;

        NewsLoadingViewHolder(View itemView) {
            super(itemView);
            this.mLinearLayout = (LinearLayout) itemView.findViewById(R.id.card_layout);
        }
    }

    public static class NewsViewHolder extends RecyclerView.ViewHolder {
        LinearLayout mLinearLayout;

        NewsViewHolder(View itemView) {
            super(itemView);
            this.mLinearLayout = (LinearLayout) itemView.findViewById(R.id.card_layout);
        }
    }

    public static class NoSourcesViewHolder extends RecyclerView.ViewHolder {
        Button mBtnChooseContent;

        NoSourcesViewHolder(View itemView) {
            super(itemView);
            this.mBtnChooseContent = (Button) itemView.findViewById(R.id.btn_choose_content);
        }
    }
}
