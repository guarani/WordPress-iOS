import UIKit
import WordPressFlux

enum InsightType: Int {
    case customize
    case latestPostSummary
    case allTimeStats
    case followersTotals
    case mostPopularTime
    case tagsAndCategories
    case annualSiteStats
    case comments
    case followers
    case todaysStats
    case postingActivity
    case publicize

    // These Insights will be displayed in this order if a site's Insights have not been customized.
    static let defaultInsights = [InsightType.postingActivity,
                                  .todaysStats,
                                  .allTimeStats,
                                  .mostPopularTime,
                                  .comments
    ]

    static let defaultInsightsValues = InsightType.defaultInsights.map { $0.rawValue }

    static func typesForValues(_ values: [Int]) -> [InsightType] {
        return values.compactMap { InsightType(rawValue: $0) }
    }

    static func valuesForTypes(_ types: [InsightType]) -> [Int] {
        return types.compactMap { $0.rawValue }
    }

    var statSection: StatSection? {
        switch self {
        case .latestPostSummary:
            return .insightsLatestPostSummary
        case .allTimeStats:
            return .insightsAllTime
        case .followersTotals:
            return .insightsFollowerTotals
        case .mostPopularTime:
            return .insightsMostPopularTime
        case .tagsAndCategories:
            return .insightsTagsAndCategories
        case .annualSiteStats:
            return .insightsAnnualSiteStats
        case .comments:
            return .insightsCommentsPosts
        case .followers:
            return .insightsFollowersEmail
        case .todaysStats:
            return .insightsTodaysStats
        case .postingActivity:
            return .insightsPostingActivity
        case .publicize:
            return .insightsPublicize
        default:
            return nil
        }
    }

}

@objc protocol SiteStatsInsightsDelegate {
    @objc optional func displayWebViewWithURL(_ url: URL)
    @objc optional func showCreatePost()
    @objc optional func showShareForPost(postID: NSNumber, fromView: UIView)
    @objc optional func showPostingActivityDetails()
    @objc optional func tabbedTotalsCellUpdated()
    @objc optional func expandedRowUpdated(_ row: StatsTotalRow, didSelectRow: Bool)
    @objc optional func viewMoreSelectedForStatSection(_ statSection: StatSection)
    @objc optional func showPostStats(postID: Int, postTitle: String?, postURL: URL?)
    @objc optional func customizeDismissButtonTapped()
    @objc optional func customizeTryButtonTapped()
    @objc optional func showAddInsight()
    @objc optional func addInsightSelected(_ insight: StatSection)

}

class SiteStatsInsightsTableViewController: UITableViewController, StoryboardLoadable {
    static var defaultStoryboardName: String = "SiteStatsDashboard"

    // MARK: - Properties

    private var insightsChangeReceipt: Receipt?

    // Types of Insights to display. The array order dictates the display order.
    private var insightsToShow = [InsightType]()
    private let userDefaultsInsightTypesKey = "StatsInsightTypes"

    // Store 'customize' separately as it is not per site.
    private let userDefaultsHideCustomizeKey = "StatsInsightsHideCustomizeCard"
    private var hideCustomizeCard = false

    // Store Insights settings for all sites.
    // Used when writing to/reading from User Defaults.
    // A single site's dictionary contains the InsightType values for that site.
    private var allSitesInsights = [SiteInsights]()
    private typealias SiteInsights = [String: [Int]]

    private let asyncLoadingActivated = Feature.enabled(.statsAsyncLoading)

    private lazy var mainContext: NSManagedObjectContext = {
        return ContextManager.sharedInstance().mainContext
    }()

    private lazy var blogService: BlogService = {
        return BlogService(managedObjectContext: mainContext)
    }()

    private lazy var postService: PostService = {
        return PostService(managedObjectContext: mainContext)
    }()

    private var viewModel: SiteStatsInsightsViewModel?

    private let analyticsTracker = BottomScrollAnalyticsTracker()

    private lazy var tableHandler: ImmuTableViewHandler = {
        return ImmuTableViewHandler(takeOver: self, with: analyticsTracker)
    }()

    // MARK: - View

    override func viewDidLoad() {
        super.viewDidLoad()

        clearExpandedRows()
        WPStyleGuide.Stats.configureTable(tableView)
        refreshControl?.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        ImmuTable.registerRows(tableRowTypes(), tableView: tableView)
        loadInsightsFromUserDefaults()
        initViewModel()
        tableView.estimatedRowHeight = 500

        if !asyncLoadingActivated {
            displayLoadingViewIfNecessary()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        writeInsightsToUserDefaults()
    }

    func refreshInsights() {
        addViewModelListeners()
        viewModel?.refreshInsights()
    }
}

// MARK: - Private Extension

private extension SiteStatsInsightsTableViewController {

    func initViewModel() {
        viewModel = SiteStatsInsightsViewModel(insightsToShow: insightsToShow, insightsDelegate: self)
        addViewModelListeners()
        viewModel?.fetchInsights()
    }

    func addViewModelListeners() {
        if insightsChangeReceipt != nil {
            return
        }

        insightsChangeReceipt = viewModel?.onChange { [weak self] in
            let asyncLoadingActivated = self?.asyncLoadingActivated ?? false
            if !asyncLoadingActivated {
                if let viewModel = self?.viewModel,
                    viewModel.isFetchingOverview() {
                        return
                }
            }
            self?.refreshTableView()
        }
    }

    func removeViewModelListeners() {
        if asyncLoadingActivated {
            return
        }
        insightsChangeReceipt = nil
    }

    func tableRowTypes() -> [ImmuTableRow.Type] {
        var rows: [ImmuTableRow.Type] = [CellHeaderRow.self,
                                         CustomizeInsightsRow.self,
                                         LatestPostSummaryRow.self,
                                         TwoColumnStatsRow.self,
                                         PostingActivityRow.self,
                                         TabbedTotalsStatsRow.self,
                                         TopTotalsInsightStatsRow.self,
                                         TableFooterRow.self]
        if asyncLoadingActivated {
            rows.append(contentsOf: [StatsErrorRow.self,
                                     StatsGhostChartImmutableRow.self,
                                     StatsGhostTwoColumnImmutableRow.self,
                                     StatsGhostTopImmutableRow.self,
                                     StatsGhostTabbedImmutableRow.self,
                                     StatsGhostPostingActivitiesImmutableRow.self])
        }
        return rows
    }

    // MARK: - Table Refreshing

    func refreshTableView() {
        guard let viewModel = viewModel else {
                return
        }

        if !asyncLoadingActivated {
            guard viewIsVisible() else {
                    return
            }
        }

        tableHandler.viewModel = viewModel.tableViewModel()

        if asyncLoadingActivated {
            if viewModel.fetchingFailed() {
                displayFailureViewIfNecessary()
            }
        } else {
            if viewModel.fetchingFailed() &&
                !viewModel.containsCachedData() {
                displayFailureViewIfNecessary()
            } else {
                hideNoResults()
            }
        }

        refreshControl?.endRefreshing()
    }

    @objc func refreshData() {
        refreshControl?.beginRefreshing()
        clearExpandedRows()
        refreshInsights()
        hideNoResults()
    }

    func applyTableUpdates() {
        tableView.performBatchUpdates({
        })
    }

    func clearExpandedRows() {
        StatsDataHelper.clearExpandedInsights()
    }

    func viewIsVisible() -> Bool {
        return isViewLoaded && view.window != nil
    }

    func updateView() {
        viewModel?.updateInsightsToShow(insights: insightsToShow)
        refreshTableView()
    }

    // MARK: User Defaults

    func loadInsightsFromUserDefaults() {
        guard let siteID = SiteStatsInformation.sharedInstance.siteID?.stringValue else {
            insightsToShow = InsightType.defaultInsights
            loadCustomizeCardSetting()
            return
        }

        // Get Insights from User Defaults, and extract those for the current site.
        allSitesInsights = UserDefaults.standard.object(forKey: userDefaultsInsightTypesKey) as? [SiteInsights] ?? []
        let siteInsights = allSitesInsights.first { $0.keys.first == siteID }

        // If no Insights for the current site, use the default Insights.
        let insightTypesValues = siteInsights?.values.first ?? InsightType.defaultInsightsValues
        insightsToShow = InsightType.typesForValues(insightTypesValues)

        // Add the 'customize' card if necessary.
        loadCustomizeCardSetting()
    }

    func writeInsightsToUserDefaults() {
        writeCustomizeCardSetting()

        guard let siteID = SiteStatsInformation.sharedInstance.siteID?.stringValue else {
            return
        }

        // Remove 'customize' from array since it is not per site.
        removeCustomizeCard()

        let insightTypesValues = InsightType.valuesForTypes(insightsToShow)
        let currentSiteInsights = [siteID: insightTypesValues]

        // Remove existing dictionary from array, and add the updated one.
        allSitesInsights = allSitesInsights.filter { $0.keys.first != siteID }
        allSitesInsights.append(currentSiteInsights)

        UserDefaults.standard.set(allSitesInsights, forKey: userDefaultsInsightTypesKey)
    }

    func loadCustomizeCardSetting() {
        hideCustomizeCard = UserDefaults.standard.bool(forKey: userDefaultsHideCustomizeKey)

        if !hideCustomizeCard {
            // Insert customize at the beginning of the array so it is displayed first.
            insightsToShow.insert(.customize, at: 0)
        }
    }

    func writeCustomizeCardSetting() {
        UserDefaults.standard.set(hideCustomizeCard, forKey: userDefaultsHideCustomizeKey)
    }

    func removeCustomizeCard() {
        insightsToShow = insightsToShow.filter { $0 != .customize }
    }

    // MARK: - Insights Management

    func showAddInsightView() {
        let controller = AddInsightTableViewController(insightsDelegate: self,
                                                       insightsShown: insightsToShow.compactMap { $0.statSection })
        navigationController?.pushViewController(controller, animated: true)
    }

}

extension SiteStatsInsightsTableViewController: NoResultsViewHost {
    private func displayLoadingViewIfNecessary() {
        guard tableHandler.viewModel.sections.isEmpty else {
            return
        }

        configureAndDisplayNoResults(on: tableView,
                                     title: NoResultConstants.successTitle,
                                     accessoryView: NoResultsViewController.loadingAccessoryView()) { [weak self] noResults in
                                        noResults.delegate = self
                                        noResults.hideImageView(false)
        }
    }

    private func displayFailureViewIfNecessary() {
        guard tableHandler.viewModel.sections.isEmpty else {
            return
        }

        if asyncLoadingActivated {
            configureAndDisplayNoResults(on: tableView,
                                         title: NoResultConstants.errorTitle,
                                         subtitle: NoResultConstants.errorSubtitle,
                                         buttonTitle: NoResultConstants.refreshButtonTitle) { [weak self] noResults in
                                            noResults.delegate = self
                                            if !noResults.isReachable {
                                                noResults.resetButtonText()
                                            }
            }
        } else {
            updateNoResults(title: NoResultConstants.errorTitle,
                            subtitle: NoResultConstants.errorSubtitle,
                            buttonTitle: NoResultConstants.refreshButtonTitle) { [weak self] noResults in
                                noResults.delegate = self
                                noResults.hideImageView()
            }
        }
    }

    private enum NoResultConstants {
        static let successTitle = NSLocalizedString("Loading Stats...", comment: "The loading view title displayed while the service is loading")
        static let errorTitle = NSLocalizedString("Stats not loaded", comment: "The loading view title displayed when an error occurred")
        static let errorSubtitle = NSLocalizedString("There was a problem loading your data, refresh your page to try again.", comment: "The loading view subtitle displayed when an error occurred")
        static let refreshButtonTitle = NSLocalizedString("Refresh", comment: "The loading view button title displayed when an error occurred")
    }
}

// MARK: - SiteStatsInsightsDelegate Methods

extension SiteStatsInsightsTableViewController: SiteStatsInsightsDelegate {

    func displayWebViewWithURL(_ url: URL) {
        let webViewController = WebViewControllerFactory.controllerAuthenticatedWithDefaultAccount(url: url)
        let navController = UINavigationController.init(rootViewController: webViewController)
        present(navController, animated: true)
    }

    func showCreatePost() {
        WPTabBarController.sharedInstance().showPostTab { [weak self] in
            self?.refreshInsights()
        }
    }

    func showShareForPost(postID: NSNumber, fromView: UIView) {
        guard let blogId = SiteStatsInformation.sharedInstance.siteID,
        let blog = blogService.blog(byBlogId: blogId) else {
            DDLogInfo("Failed to get blog with id \(String(describing: SiteStatsInformation.sharedInstance.siteID))")
            return
        }

        postService.getPostWithID(postID, for: blog, success: { apost in
            guard let post = apost as? Post else {
                DDLogInfo("Failed to get post with id \(postID)")
                return
            }

            let shareController = PostSharingController()
            shareController.sharePost(post, fromView: fromView, inViewController: self)
        }, failure: { error in
            DDLogInfo("Error getting post with id \(postID): \(error.localizedDescription)")
        })
    }

    func showPostingActivityDetails() {
        guard let viewModel = viewModel else {
            return
        }

        let postingActivityViewController = PostingActivityViewController.loadFromStoryboard()
        postingActivityViewController.yearData = viewModel.yearlyPostingActivity()
        navigationController?.pushViewController(postingActivityViewController, animated: true)
    }

    func tabbedTotalsCellUpdated() {
        applyTableUpdates()
    }

    func expandedRowUpdated(_ row: StatsTotalRow, didSelectRow: Bool) {
        if didSelectRow {
            applyTableUpdates()
        }
        StatsDataHelper.updatedExpandedState(forRow: row)
    }

    func viewMoreSelectedForStatSection(_ statSection: StatSection) {
        guard StatSection.allInsights.contains(statSection) else {
            return
        }

        removeViewModelListeners()

        // When displaying Annual details, start from the most recent year available.
        var selectedDate: Date?
        if statSection == .insightsAnnualSiteStats,
            let year = viewModel?.annualInsightsYear() {
            var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: StatsDataHelper.currentDateForSite())
            dateComponents.year = year
            selectedDate = Calendar.current.date(from: dateComponents)
        }

        let detailTableViewController = SiteStatsDetailTableViewController.loadFromStoryboard()
        detailTableViewController.configure(statSection: statSection, selectedDate: selectedDate)
        navigationController?.pushViewController(detailTableViewController, animated: true)
    }

    func showPostStats(postID: Int, postTitle: String?, postURL: URL?) {
        removeViewModelListeners()

        let postStatsTableViewController = PostStatsTableViewController.loadFromStoryboard()
        postStatsTableViewController.configure(postID: postID, postTitle: postTitle, postURL: postURL)
        navigationController?.pushViewController(postStatsTableViewController, animated: true)
    }

    func customizeDismissButtonTapped() {
        hideCustomizeCard = true
        removeCustomizeCard()
        updateView()
    }

    func customizeTryButtonTapped() {
        showAddInsightView()
    }

    func showAddInsight() {
        showAddInsightView()
    }

    func addInsightSelected(_ insight: StatSection) {
        guard let insightType = insight.insightType,
            !insightsToShow.contains(insightType) else {
                return
        }

        insightsToShow.append(insightType)
        updateView()
    }

}

extension SiteStatsInsightsTableViewController: NoResultsViewControllerDelegate {
    func actionButtonPressed() {
        if asyncLoadingActivated {
            hideNoResults()
        } else {
            updateNoResults(title: NoResultConstants.successTitle,
                            accessoryView: NoResultsViewController.loadingAccessoryView()) { noResults in
                                noResults.hideImageView(false)
            }
        }
        addViewModelListeners()
        refreshInsights()
    }
}
