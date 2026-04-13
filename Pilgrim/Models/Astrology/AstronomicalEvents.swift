import Foundation

/// Pre-computed tables of rare astronomical events for the Walk Light
/// Reading feature. Data is hand-curated from authoritative sources:
/// - Lunar eclipses: NASA Goddard 5000-year canon
/// - Supermoons: Fred Espenak's perigee-syzygy tables
/// - Meteor showers: IMO major shower list (annual recurrences)
///
/// Coverage: 2026-2100. When the coverage window starts running short
/// (roughly 2097+), re-fetch the source data and regenerate this file.
///
/// Rationale for static tables vs. runtime computation: lunar eclipses
/// and supermoons are historical facts, not predictions — we don't need
/// ephemeris math at runtime to know them. Static tables are faster,
/// smaller, and have zero accuracy risk from algorithm choice.
enum AstronomicalEvents {

    // MARK: - Lunar eclipses 2026-2100
    // Source: https://eclipse.gsfc.nasa.gov/LEcat5/LE2001-2100.html
    // unixTime is the instant of maximum eclipse in UTC.
    // Penumbral magnitude is stored as 0.0 (umbral magnitude is negative
    // for penumbral eclipses, which is meaningless for display purposes).
    static let lunarEclipses: [LunarEclipseEvent] = [
        LunarEclipseEvent(unixTime: 1772537598, type: .total,      magnitude: 1.151),   // 2026-03-03T11:33:18Z
        LunarEclipseEvent(unixTime: 1787890444, type: .partial,    magnitude: 0.9299),  // 2026-08-28T04:14:04Z
        LunarEclipseEvent(unixTime: 1803165246, type: .penumbral,  magnitude: 0.0),     // 2027-02-20T23:14:06Z
        LunarEclipseEvent(unixTime: 1815926649, type: .penumbral,  magnitude: 0.0),     // 2027-07-18T16:04:09Z
        LunarEclipseEvent(unixTime: 1818486899, type: .penumbral,  magnitude: 0.0),     // 2027-08-17T07:14:59Z
        LunarEclipseEvent(unixTime: 1831263253, type: .partial,    magnitude: 0.0662),  // 2028-01-12T04:14:13Z
        LunarEclipseEvent(unixTime: 1846520457, type: .partial,    magnitude: 0.3892),  // 2028-07-06T18:20:57Z
        LunarEclipseEvent(unixTime: 1861894395, type: .total,      magnitude: 1.2463),  // 2028-12-31T16:53:15Z
        LunarEclipseEvent(unixTime: 1877138602, type: .total,      magnitude: 1.8436),  // 2029-06-26T03:23:22Z
        LunarEclipseEvent(unixTime: 1892500992, type: .total,      magnitude: 1.1174),  // 2029-12-20T22:43:12Z
        LunarEclipseEvent(unixTime: 1907778874, type: .partial,    magnitude: 0.5025),  // 2030-06-15T18:34:34Z
        LunarEclipseEvent(unixTime: 1923085731, type: .penumbral,  magnitude: 0.0),     // 2030-12-09T22:28:51Z
        LunarEclipseEvent(unixTime: 1935892322, type: .penumbral,  magnitude: 0.0),     // 2031-05-07T03:52:02Z
        LunarEclipseEvent(unixTime: 1938426317, type: .penumbral,  magnitude: 0.0),     // 2031-06-05T11:45:17Z
        LunarEclipseEvent(unixTime: 1951112805, type: .penumbral,  magnitude: 0.0),     // 2031-10-30T07:46:45Z
        LunarEclipseEvent(unixTime: 1966518891, type: .total,      magnitude: 1.1913),  // 2032-04-25T15:14:51Z
        LunarEclipseEvent(unixTime: 1981739020, type: .total,      magnitude: 1.1028),  // 2032-10-18T19:03:40Z
        LunarEclipseEvent(unixTime: 1997118831, type: .total,      magnitude: 1.0944),  // 2033-04-14T19:13:51Z
        LunarEclipseEvent(unixTime: 2012381783, type: .total,      magnitude: 1.3497),  // 2033-10-08T10:56:23Z
        LunarEclipseEvent(unixTime: 2027704019, type: .penumbral,  magnitude: 0.0),     // 2034-04-03T19:06:59Z
        LunarEclipseEvent(unixTime: 2043024457, type: .partial,    magnitude: 0.0144),  // 2034-09-28T02:47:37Z
        LunarEclipseEvent(unixTime: 2055747972, type: .penumbral,  magnitude: 0.0),     // 2035-02-22T09:06:12Z
        LunarEclipseEvent(unixTime: 2071098735, type: .partial,    magnitude: 0.1037),  // 2035-08-19T01:12:15Z
        LunarEclipseEvent(unixTime: 2086380786, type: .total,      magnitude: 1.2995),  // 2036-02-11T22:13:06Z
        LunarEclipseEvent(unixTime: 2101690352, type: .total,      magnitude: 1.4544),  // 2036-08-07T02:52:32Z
        LunarEclipseEvent(unixTime: 2117023298, type: .total,      magnitude: 1.2074),  // 2037-01-31T14:01:38Z
        LunarEclipseEvent(unixTime: 2132280593, type: .partial,    magnitude: 0.8095),  // 2037-07-27T04:09:53Z
        LunarEclipseEvent(unixTime: 2147658592, type: .penumbral,  magnitude: 0.0),     // 2038-01-21T03:49:52Z
        LunarEclipseEvent(unixTime: 2160355502, type: .penumbral,  magnitude: 0.0),     // 2038-06-17T02:45:02Z
        LunarEclipseEvent(unixTime: 2162892956, type: .penumbral,  magnitude: 0.0),     // 2038-07-16T11:35:56Z
        LunarEclipseEvent(unixTime: 2175702300, type: .penumbral,  magnitude: 0.0),     // 2038-12-11T17:45:00Z
        LunarEclipseEvent(unixTime: 2190999265, type: .partial,    magnitude: 0.8846),  // 2039-06-06T18:54:25Z
        LunarEclipseEvent(unixTime: 2206284988, type: .partial,    magnitude: 0.9426),  // 2039-11-30T16:56:28Z
        LunarEclipseEvent(unixTime: 2221645582, type: .total,      magnitude: 1.5348),  // 2040-05-26T11:46:22Z
        LunarEclipseEvent(unixTime: 2236878280, type: .total,      magnitude: 1.3974),  // 2040-11-18T19:04:40Z
        LunarEclipseEvent(unixTime: 2252277783, type: .partial,    magnitude: 0.0645),  // 2041-05-16T00:43:03Z
        LunarEclipseEvent(unixTime: 2267498105, type: .partial,    magnitude: 0.1696),  // 2041-11-08T04:35:05Z
        LunarEclipseEvent(unixTime: 2280321011, type: .penumbral,  magnitude: 0.0),     // 2042-04-05T14:30:11Z
        LunarEclipseEvent(unixTime: 2295600347, type: .penumbral,  magnitude: 0.0),     // 2042-09-29T10:45:47Z
        LunarEclipseEvent(unixTime: 2310906724, type: .total,      magnitude: 1.1142),  // 2043-03-25T14:32:04Z
        LunarEclipseEvent(unixTime: 2326240310, type: .total,      magnitude: 1.2556),  // 2043-09-19T01:51:50Z
        LunarEclipseEvent(unixTime: 2341510713, type: .total,      magnitude: 1.2031),  // 2044-03-13T19:38:33Z
        LunarEclipseEvent(unixTime: 2356860044, type: .total,      magnitude: 1.0456),  // 2044-09-07T11:20:44Z
        LunarEclipseEvent(unixTime: 2372139806, type: .penumbral,  magnitude: 0.0),     // 2045-03-03T07:43:26Z
        LunarEclipseEvent(unixTime: 2387454890, type: .penumbral,  magnitude: 0.0),     // 2045-08-27T13:54:50Z
        LunarEclipseEvent(unixTime: 2400238957, type: .partial,    magnitude: 0.0532),  // 2046-01-22T13:02:37Z
        LunarEclipseEvent(unixTime: 2415488765, type: .partial,    magnitude: 0.2461),  // 2046-07-18T01:06:05Z
        LunarEclipseEvent(unixTime: 2430869174, type: .total,      magnitude: 1.2341),  // 2047-01-12T01:26:14Z
        LunarEclipseEvent(unixTime: 2446108545, type: .total,      magnitude: 1.7513),  // 2047-07-07T10:35:45Z
        LunarEclipseEvent(unixTime: 2461474435, type: .total,      magnitude: 1.1280),  // 2048-01-01T06:53:55Z
        LunarEclipseEvent(unixTime: 2476749748, type: .partial,    magnitude: 0.6388),  // 2048-06-26T02:02:28Z
        LunarEclipseEvent(unixTime: 2492058468, type: .penumbral,  magnitude: 0.0),     // 2048-12-20T06:27:48Z
        LunarEclipseEvent(unixTime: 2504863599, type: .penumbral,  magnitude: 0.0),     // 2049-05-17T11:26:39Z
        LunarEclipseEvent(unixTime: 2507397252, type: .penumbral,  magnitude: 0.0),     // 2049-06-15T19:14:12Z
        LunarEclipseEvent(unixTime: 2520085931, type: .penumbral,  magnitude: 0.0),     // 2049-11-09T15:52:11Z
        LunarEclipseEvent(unixTime: 2535489122, type: .total,      magnitude: 1.0767),  // 2050-05-06T22:32:02Z
        LunarEclipseEvent(unixTime: 2550712907, type: .total,      magnitude: 1.0538),  // 2050-10-30T03:21:47Z
        LunarEclipseEvent(unixTime: 2566088188, type: .total,      magnitude: 1.2022),  // 2051-04-26T02:16:28Z
        LunarEclipseEvent(unixTime: 2581355510, type: .total,      magnitude: 1.4118),  // 2051-10-19T19:11:50Z
        LunarEclipseEvent(unixTime: 2596673886, type: .penumbral,  magnitude: 0.0),     // 2052-04-14T02:18:06Z
        LunarEclipseEvent(unixTime: 2611997158, type: .partial,    magnitude: 0.0821),  // 2052-10-08T10:45:58Z
        LunarEclipseEvent(unixTime: 2624721730, type: .penumbral,  magnitude: 0.0),     // 2053-03-04T17:22:10Z
        LunarEclipseEvent(unixTime: 2640067550, type: .penumbral,  magnitude: 0.0),     // 2053-08-29T08:05:50Z
        LunarEclipseEvent(unixTime: 2655355887, type: .total,      magnitude: 1.2769),  // 2054-02-22T06:51:27Z
        LunarEclipseEvent(unixTime: 2670657990, type: .total,      magnitude: 1.3062),  // 2054-08-18T09:26:30Z
        LunarEclipseEvent(unixTime: 2685998777, type: .total,      magnitude: 1.2246),  // 2055-02-11T22:46:17Z
        LunarEclipseEvent(unixTime: 2701248798, type: .partial,    magnitude: 0.9594),  // 2055-08-07T10:53:18Z
        LunarEclipseEvent(unixTime: 2716633566, type: .penumbral,  magnitude: 0.0),     // 2056-02-01T12:26:06Z
        LunarEclipseEvent(unixTime: 2729325789, type: .penumbral,  magnitude: 0.0),     // 2056-06-27T10:03:09Z
        LunarEclipseEvent(unixTime: 2731862604, type: .penumbral,  magnitude: 0.0),     // 2056-07-26T18:43:24Z
        LunarEclipseEvent(unixTime: 2744675336, type: .penumbral,  magnitude: 0.0),     // 2056-12-22T01:48:56Z
        LunarEclipseEvent(unixTime: 2759970380, type: .partial,    magnitude: 0.7555),  // 2057-06-17T02:26:20Z
        LunarEclipseEvent(unixTime: 2775257618, type: .partial,    magnitude: 0.9181),  // 2057-12-11T00:53:38Z
        LunarEclipseEvent(unixTime: 2790616548, type: .total,      magnitude: 1.6611),  // 2058-06-06T19:15:48Z
        LunarEclipseEvent(unixTime: 2805851778, type: .total,      magnitude: 1.4260),  // 2058-11-30T03:16:18Z
        LunarEclipseEvent(unixTime: 2821247735, type: .partial,    magnitude: 0.1829),  // 2059-05-27T07:55:35Z
        LunarEclipseEvent(unixTime: 2836472496, type: .partial,    magnitude: 0.2079),  // 2059-11-19T13:01:36Z
        LunarEclipseEvent(unixTime: 2849290624, type: .penumbral,  magnitude: 0.0),     // 2060-04-15T21:37:04Z
        LunarEclipseEvent(unixTime: 2864573612, type: .penumbral,  magnitude: 0.0),     // 2060-10-09T18:53:32Z
        LunarEclipseEvent(unixTime: 2867112255, type: .penumbral,  magnitude: 0.0),     // 2060-11-08T04:04:15Z
        LunarEclipseEvent(unixTime: 2879877245, type: .total,      magnitude: 1.0341),  // 2061-04-04T21:54:05Z
        LunarEclipseEvent(unixTime: 2895212293, type: .total,      magnitude: 1.1621),  // 2061-09-29T09:38:13Z
        LunarEclipseEvent(unixTime: 2910483230, type: .total,      magnitude: 1.2695),  // 2062-03-25T03:33:50Z
        LunarEclipseEvent(unixTime: 2925830042, type: .total,      magnitude: 1.1496),  // 2062-09-18T18:34:02Z
        LunarEclipseEvent(unixTime: 2941113949, type: .partial,    magnitude: 0.0342),  // 2063-03-14T16:05:49Z
        LunarEclipseEvent(unixTime: 2956423272, type: .penumbral,  magnitude: 0.0),     // 2063-09-07T20:41:12Z
        LunarEclipseEvent(unixTime: 2969214537, type: .partial,    magnitude: 0.0377),  // 2064-02-02T21:48:57Z
        LunarEclipseEvent(unixTime: 2984457168, type: .partial,    magnitude: 0.1038),  // 2064-07-28T07:52:48Z
        LunarEclipseEvent(unixTime: 2999843938, type: .total,      magnitude: 1.2231),  // 2065-01-22T09:58:58Z
        LunarEclipseEvent(unixTime: 3015078520, type: .total,      magnitude: 1.6121),  // 2065-07-17T17:48:40Z
        LunarEclipseEvent(unixTime: 3030447887, type: .total,      magnitude: 1.1378),  // 2066-01-11T15:04:47Z
        LunarEclipseEvent(unixTime: 3045720629, type: .partial,    magnitude: 0.7753),  // 2066-07-07T09:30:29Z
        LunarEclipseEvent(unixTime: 3061031410, type: .penumbral,  magnitude: 0.0),     // 2066-12-31T14:30:10Z
        LunarEclipseEvent(unixTime: 3073834568, type: .penumbral,  magnitude: 0.0),     // 2067-05-28T18:56:08Z
        LunarEclipseEvent(unixTime: 3076368066, type: .penumbral,  magnitude: 0.0),     // 2067-06-27T02:41:06Z
        LunarEclipseEvent(unixTime: 3089059482, type: .penumbral,  magnitude: 0.0),     // 2067-11-21T00:04:42Z
        LunarEclipseEvent(unixTime: 3104458937, type: .partial,    magnitude: 0.9532),  // 2068-05-17T05:42:17Z
        LunarEclipseEvent(unixTime: 3119687220, type: .total,      magnitude: 1.0149),  // 2068-11-09T11:47:00Z
        LunarEclipseEvent(unixTime: 3135056997, type: .total,      magnitude: 1.3229),  // 2069-05-06T09:09:57Z
        LunarEclipseEvent(unixTime: 3150329706, type: .total,      magnitude: 1.4616),  // 2069-10-30T03:35:06Z
        LunarEclipseEvent(unixTime: 3165643284, type: .penumbral,  magnitude: 0.0),     // 2070-04-25T09:21:24Z
        LunarEclipseEvent(unixTime: 3180970272, type: .partial,    magnitude: 0.1383),  // 2070-10-19T18:51:12Z
        LunarEclipseEvent(unixTime: 3193695069, type: .penumbral,  magnitude: 0.0),     // 2071-03-16T01:31:09Z
        LunarEclipseEvent(unixTime: 3209036741, type: .penumbral,  magnitude: 0.0),     // 2071-09-09T15:05:41Z
        LunarEclipseEvent(unixTime: 3224330587, type: .total,      magnitude: 1.2441),  // 2072-03-04T15:23:07Z
        LunarEclipseEvent(unixTime: 3239625942, type: .total,      magnitude: 1.1662),  // 2072-08-28T16:05:42Z
        LunarEclipseEvent(unixTime: 3254973893, type: .total,      magnitude: 1.2503),  // 2073-02-22T07:24:53Z
        LunarEclipseEvent(unixTime: 3270217361, type: .total,      magnitude: 1.1013),  // 2073-08-17T17:42:41Z
        LunarEclipseEvent(unixTime: 3285608158, type: .penumbral,  magnitude: 0.0),     // 2074-02-11T20:55:58Z
        LunarEclipseEvent(unixTime: 3298296098, type: .penumbral,  magnitude: 0.0),     // 2074-07-08T17:21:38Z
        LunarEclipseEvent(unixTime: 3300832563, type: .penumbral,  magnitude: 0.0),     // 2074-08-07T01:56:03Z
        LunarEclipseEvent(unixTime: 3313648503, type: .penumbral,  magnitude: 0.0),     // 2075-01-02T09:55:03Z
        LunarEclipseEvent(unixTime: 3328941335, type: .partial,    magnitude: 0.6220),  // 2075-06-28T09:55:35Z
        LunarEclipseEvent(unixTime: 3344230555, type: .partial,    magnitude: 0.9013),  // 2075-12-22T08:55:55Z
        LunarEclipseEvent(unixTime: 3359587187, type: .total,      magnitude: 1.7943),  // 2076-06-17T02:39:47Z
        LunarEclipseEvent(unixTime: 3374825691, type: .total,      magnitude: 1.4460),  // 2076-12-10T11:34:51Z
        LunarEclipseEvent(unixTime: 3390217192, type: .partial,    magnitude: 0.3123),  // 2077-06-06T14:59:52Z
        LunarEclipseEvent(unixTime: 3405447353, type: .partial,    magnitude: 0.2356),  // 2077-11-29T21:35:53Z
        LunarEclipseEvent(unixTime: 3418259744, type: .penumbral,  magnitude: 0.0),     // 2078-04-27T04:35:44Z
        LunarEclipseEvent(unixTime: 3433547283, type: .penumbral,  magnitude: 0.0),     // 2078-10-21T03:08:03Z
        LunarEclipseEvent(unixTime: 3436087204, type: .penumbral,  magnitude: 0.0),     // 2078-11-19T12:40:04Z
        LunarEclipseEvent(unixTime: 3448847445, type: .partial,    magnitude: 0.9451),  // 2079-04-16T05:10:45Z
        LunarEclipseEvent(unixTime: 3464184630, type: .total,      magnitude: 1.0791),  // 2079-10-10T17:30:30Z
        LunarEclipseEvent(unixTime: 3479455418, type: .total,      magnitude: 1.3460),  // 2080-04-04T11:23:38Z
        LunarEclipseEvent(unixTime: 3494800362, type: .total,      magnitude: 1.2443),  // 2080-09-29T01:52:42Z
        LunarEclipseEvent(unixTime: 3510087721, type: .partial,    magnitude: 0.0953),  // 2081-03-25T00:22:01Z
        LunarEclipseEvent(unixTime: 3525392126, type: .penumbral,  magnitude: 0.0),     // 2081-09-18T03:35:26Z
        LunarEclipseEvent(unixTime: 3538189759, type: .partial,    magnitude: 0.0134),  // 2082-02-13T06:29:19Z
        LunarEclipseEvent(unixTime: 3553426002, type: .penumbral,  magnitude: 0.0),     // 2082-08-08T14:46:42Z
        LunarEclipseEvent(unixTime: 3568818406, type: .total,      magnitude: 1.2052),  // 2083-02-02T18:26:46Z
        LunarEclipseEvent(unixTime: 3584048734, type: .total,      magnitude: 1.4773),  // 2083-07-29T01:05:34Z
        LunarEclipseEvent(unixTime: 3599421180, type: .total,      magnitude: 1.1513),  // 2084-01-22T23:13:00Z
        LunarEclipseEvent(unixTime: 3614691531, type: .partial,    magnitude: 0.9119),  // 2084-07-17T16:58:51Z
        LunarEclipseEvent(unixTime: 3630004349, type: .penumbral,  magnitude: 0.0),     // 2085-01-10T22:32:29Z
        LunarEclipseEvent(unixTime: 3642805056, type: .penumbral,  magnitude: 0.0),     // 2085-06-08T02:17:36Z
        LunarEclipseEvent(unixTime: 3645338680, type: .penumbral,  magnitude: 0.0),     // 2085-07-07T10:04:40Z
        LunarEclipseEvent(unixTime: 3658033535, type: .penumbral,  magnitude: 0.0),     // 2085-12-01T08:25:35Z
        LunarEclipseEvent(unixTime: 3673428227, type: .partial,    magnitude: 0.8180),  // 2086-05-28T12:43:47Z
        LunarEclipseEvent(unixTime: 3688661982, type: .partial,    magnitude: 0.9865),  // 2086-11-20T20:19:42Z
        LunarEclipseEvent(unixTime: 3704025320, type: .total,      magnitude: 1.4554),  // 2087-05-17T15:55:20Z
        LunarEclipseEvent(unixTime: 3719304333, type: .total,      magnitude: 1.5006),  // 2087-11-10T12:05:33Z
        LunarEclipseEvent(unixTime: 3734612210, type: .partial,    magnitude: 0.1019),  // 2088-05-05T16:16:50Z
        LunarEclipseEvent(unixTime: 3749943800, type: .partial,    magnitude: 0.1831),  // 2088-10-30T03:03:20Z
        LunarEclipseEvent(unixTime: 3762668054, type: .penumbral,  magnitude: 0.0),     // 2089-03-26T09:34:14Z
        LunarEclipseEvent(unixTime: 3778006277, type: .penumbral,  magnitude: 0.0),     // 2089-09-19T22:11:17Z
        LunarEclipseEvent(unixTime: 3793304911, type: .total,      magnitude: 1.2012),  // 2090-03-15T23:48:31Z
        LunarEclipseEvent(unixTime: 3808594349, type: .total,      magnitude: 1.0377),  // 2090-09-08T22:52:29Z
        LunarEclipseEvent(unixTime: 3823948702, type: .total,      magnitude: 1.2832),  // 2091-03-05T15:58:22Z
        LunarEclipseEvent(unixTime: 3839186305, type: .total,      magnitude: 1.2351),  // 2091-08-29T00:38:25Z
        LunarEclipseEvent(unixTime: 3854582459, type: .penumbral,  magnitude: 0.0),     // 2092-02-23T05:20:59Z
        LunarEclipseEvent(unixTime: 3869802839, type: .penumbral,  magnitude: 0.0),     // 2092-08-17T09:13:59Z
        LunarEclipseEvent(unixTime: 3882621603, type: .penumbral,  magnitude: 0.0),     // 2093-01-12T18:00:03Z
        LunarEclipseEvent(unixTime: 3897912258, type: .partial,    magnitude: 0.4872),  // 2093-07-08T17:24:18Z
        LunarEclipseEvent(unixTime: 3913203606, type: .partial,    magnitude: 0.8871),  // 2094-01-01T17:00:06Z
        LunarEclipseEvent(unixTime: 3928557717, type: .total,      magnitude: 1.8234),  // 2094-06-28T10:01:57Z
        LunarEclipseEvent(unixTime: 3943799792, type: .total,      magnitude: 1.4627),  // 2094-12-21T19:56:32Z
        LunarEclipseEvent(unixTime: 3959186411, type: .partial,    magnitude: 0.4459),  // 2095-06-17T22:00:11Z
        LunarEclipseEvent(unixTime: 3974422502, type: .partial,    magnitude: 0.2565),  // 2095-12-11T06:15:02Z
        LunarEclipseEvent(unixTime: 3987228282, type: .penumbral,  magnitude: 0.0),     // 2096-05-07T11:24:42Z
        LunarEclipseEvent(unixTime: 4002521423, type: .penumbral,  magnitude: 0.0),     // 2096-10-31T11:30:23Z
        LunarEclipseEvent(unixTime: 4005062542, type: .penumbral,  magnitude: 0.0),     // 2096-11-29T21:22:22Z
        LunarEclipseEvent(unixTime: 4017817097, type: .partial,    magnitude: 0.8420),  // 2097-04-26T12:18:17Z
        LunarEclipseEvent(unixTime: 4033157455, type: .total,      magnitude: 1.0097),  // 2097-10-21T01:30:55Z
        LunarEclipseEvent(unixTime: 4048427088, type: .total,      magnitude: 1.4369),  // 2098-04-15T19:04:48Z
        LunarEclipseEvent(unixTime: 4063771198, type: .total,      magnitude: 1.3246),  // 2098-10-10T09:19:58Z
        LunarEclipseEvent(unixTime: 4079061056, type: .partial,    magnitude: 0.1680),  // 2099-04-05T08:30:56Z
        LunarEclipseEvent(unixTime: 4094361398, type: .penumbral,  magnitude: 0.0),     // 2099-09-29T10:36:38Z
        LunarEclipseEvent(unixTime: 4107164711, type: .penumbral,  magnitude: 0.0),     // 2100-02-24T15:05:11Z
        LunarEclipseEvent(unixTime: 4122395098, type: .penumbral,  magnitude: 0.0),     // 2100-08-19T21:44:58Z
    ]

    // MARK: - Supermoons 2026-2100
    // Source: Fred Espenak, https://www.astropixels.com/ephemeris/moon/fullperigee2001.html
    // Criterion: full moon with lunar distance ≤ 360,000 km.
    static let supermoons: [SupermoonEvent] = [
        SupermoonEvent(unixTime: 1798075680, distanceKm: 356_740),  // 2026-12-24T01:28Z
        SupermoonEvent(unixTime: 1800620220, distanceKm: 357_644),  // 2027-01-22T12:17Z
        SupermoonEvent(unixTime: 1833807840, distanceKm: 356_720),  // 2028-02-10T15:04Z
        SupermoonEvent(unixTime: 1836349560, distanceKm: 358_074),  // 2028-03-11T01:06Z
        SupermoonEvent(unixTime: 1866993000, distanceKm: 359_659),  // 2029-02-28T17:10Z
        SupermoonEvent(unixTime: 1869531960, distanceKm: 356_683),  // 2029-03-30T02:26Z
        SupermoonEvent(unixTime: 1872067020, distanceKm: 358_383),  // 2029-04-28T10:37Z
        SupermoonEvent(unixTime: 1902712800, distanceKm: 359_654),  // 2030-04-18T03:20Z
        SupermoonEvent(unixTime: 1905247140, distanceKm: 357_028),  // 2030-05-17T11:19Z
        SupermoonEvent(unixTime: 1907779260, distanceKm: 358_779),  // 2030-06-15T18:41Z
        SupermoonEvent(unixTime: 1938427080, distanceKm: 359_674),  // 2031-06-05T11:58Z
        SupermoonEvent(unixTime: 1940958060, distanceKm: 357_018),  // 2031-07-04T19:01Z
        SupermoonEvent(unixTime: 1943487960, distanceKm: 358_651),  // 2031-08-03T01:46Z
        SupermoonEvent(unixTime: 1974135060, distanceKm: 359_511),  // 2032-07-22T18:51Z
        SupermoonEvent(unixTime: 1976665620, distanceKm: 356_889),  // 2032-08-21T01:47Z
        SupermoonEvent(unixTime: 1979199000, distanceKm: 358_652),  // 2032-09-19T09:30Z
        SupermoonEvent(unixTime: 2009845200, distanceKm: 359_472),  // 2033-09-09T02:20Z
        SupermoonEvent(unixTime: 2012381880, distanceKm: 356_827),  // 2033-10-08T10:58Z
        SupermoonEvent(unixTime: 2014921920, distanceKm: 358_796),  // 2033-11-06T20:32Z
        SupermoonEvent(unixTime: 2045565720, distanceKm: 358_884),  // 2034-10-27T12:42Z
        SupermoonEvent(unixTime: 2048106720, distanceKm: 356_448),  // 2034-11-25T22:32Z
        SupermoonEvent(unixTime: 2050649640, distanceKm: 358_941),  // 2034-12-25T08:54Z
        SupermoonEvent(unixTime: 2081291580, distanceKm: 358_364),  // 2035-12-15T00:33Z
        SupermoonEvent(unixTime: 2083835760, distanceKm: 356_531),  // 2036-01-13T11:16Z
        SupermoonEvent(unixTime: 2086380540, distanceKm: 359_679),  // 2036-02-11T22:09Z
        SupermoonEvent(unixTime: 2117023440, distanceKm: 358_080),  // 2037-01-31T14:04Z
        SupermoonEvent(unixTime: 2119566480, distanceKm: 356_751),  // 2037-03-02T00:28Z
        SupermoonEvent(unixTime: 2152750140, distanceKm: 357_776),  // 2038-03-21T02:09Z
        SupermoonEvent(unixTime: 2155286160, distanceKm: 356_908),  // 2038-04-19T10:36Z
        SupermoonEvent(unixTime: 2188466400, distanceKm: 357_983),  // 2039-05-08T11:20Z
        SupermoonEvent(unixTime: 2190998880, distanceKm: 357_286),  // 2039-06-06T18:48Z
        SupermoonEvent(unixTime: 2224178340, distanceKm: 357_992),  // 2040-06-24T19:19Z
        SupermoonEvent(unixTime: 2226708300, distanceKm: 357_193),  // 2040-07-24T02:05Z
        SupermoonEvent(unixTime: 2259885840, distanceKm: 357_825),  // 2041-08-12T02:04Z
        SupermoonEvent(unixTime: 2262417840, distanceKm: 357_093),  // 2041-09-10T09:24Z
        SupermoonEvent(unixTime: 2295599640, distanceKm: 357_726),  // 2042-09-29T10:34Z
        SupermoonEvent(unixTime: 2298138480, distanceKm: 357_091),  // 2042-10-28T19:48Z
        SupermoonEvent(unixTime: 2331323520, distanceKm: 357_170),  // 2043-11-16T21:52Z
        SupermoonEvent(unixTime: 2333865720, distanceKm: 356_947),  // 2043-12-16T08:02Z
        SupermoonEvent(unixTime: 2367051600, distanceKm: 356_920),  // 2045-01-03T10:20Z
        SupermoonEvent(unixTime: 2369595900, distanceKm: 357_371),  // 2045-02-01T21:05Z
        SupermoonEvent(unixTime: 2402783040, distanceKm: 356_890),  // 2046-02-20T23:44Z
        SupermoonEvent(unixTime: 2405323620, distanceKm: 357_759),  // 2046-03-22T09:27Z
        SupermoonEvent(unixTime: 2438505300, distanceKm: 356_843),  // 2047-04-10T10:35Z
        SupermoonEvent(unixTime: 2441039040, distanceKm: 358_017),  // 2047-05-09T18:24Z
        SupermoonEvent(unixTime: 2474218620, distanceKm: 357_158),  // 2048-05-27T18:57Z
        SupermoonEvent(unixTime: 2476750080, distanceKm: 358_354),  // 2048-06-26T02:08Z
        SupermoonEvent(unixTime: 2509928940, distanceKm: 357_102),  // 2049-07-15T02:29Z
        SupermoonEvent(unixTime: 2512459140, distanceKm: 358_189),  // 2049-08-13T09:19Z
        SupermoonEvent(unixTime: 2545637460, distanceKm: 356_936),  // 2050-09-01T09:31Z
        SupermoonEvent(unixTime: 2548171920, distanceKm: 358_182),  // 2050-09-30T17:32Z
        SupermoonEvent(unixTime: 2578817460, distanceKm: 359_997),  // 2051-09-20T10:11Z
        SupermoonEvent(unixTime: 2581355580, distanceKm: 356_831),  // 2051-10-19T19:13Z
        SupermoonEvent(unixTime: 2583896760, distanceKm: 358_326),  // 2051-11-18T05:06Z
        SupermoonEvent(unixTime: 2614540140, distanceKm: 359_336),  // 2052-11-06T21:09Z
        SupermoonEvent(unixTime: 2617082280, distanceKm: 356_429),  // 2052-12-06T07:18Z
        SupermoonEvent(unixTime: 2619625560, distanceKm: 358_486),  // 2053-01-04T17:46Z
        SupermoonEvent(unixTime: 2650267380, distanceKm: 358_788),  // 2053-12-25T09:23Z
        SupermoonEvent(unixTime: 2652811680, distanceKm: 356_512),  // 2054-01-23T20:08Z
        SupermoonEvent(unixTime: 2655355620, distanceKm: 359_205),  // 2054-02-22T06:47Z
        SupermoonEvent(unixTime: 2685998880, distanceKm: 358_499),  // 2055-02-11T22:48Z
        SupermoonEvent(unixTime: 2688541020, distanceKm: 356_709),  // 2055-03-13T08:57Z
        SupermoonEvent(unixTime: 2691079140, distanceKm: 359_651),  // 2055-04-11T17:59Z
        SupermoonEvent(unixTime: 2721723900, distanceKm: 358_205),  // 2056-03-31T10:25Z
        SupermoonEvent(unixTime: 2724258660, distanceKm: 356_835),  // 2056-04-29T18:31Z
        SupermoonEvent(unixTime: 2726791080, distanceKm: 359_933),  // 2056-05-29T01:58Z
        SupermoonEvent(unixTime: 2757438120, distanceKm: 358_409),  // 2057-05-18T19:02Z
        SupermoonEvent(unixTime: 2759969940, distanceKm: 357_166),  // 2057-06-17T02:19Z
        SupermoonEvent(unixTime: 2793149220, distanceKm: 358_381),  // 2058-07-06T02:47Z
        SupermoonEvent(unixTime: 2795679480, distanceKm: 357_027),  // 2058-08-04T09:38Z
        SupermoonEvent(unixTime: 2828857320, distanceKm: 358_172),  // 2059-08-23T09:42Z
        SupermoonEvent(unixTime: 2831390340, distanceKm: 356_901),  // 2059-09-21T17:19Z
        SupermoonEvent(unixTime: 2864572860, distanceKm: 358_014),  // 2060-10-09T18:41Z
        SupermoonEvent(unixTime: 2867113080, distanceKm: 356_875),  // 2060-11-08T04:18Z
        SupermoonEvent(unixTime: 2900298780, distanceKm: 357_411),  // 2061-11-27T06:33Z
        SupermoonEvent(unixTime: 2902841580, distanceKm: 356_731),  // 2061-12-26T16:53Z
        SupermoonEvent(unixTime: 2936027520, distanceKm: 357_155),  // 2063-01-14T19:12Z
        SupermoonEvent(unixTime: 2938571340, distanceKm: 357_149),  // 2063-02-13T05:49Z
        SupermoonEvent(unixTime: 2971757940, distanceKm: 357_116),  // 2064-03-03T08:19Z
        SupermoonEvent(unixTime: 2974297200, distanceKm: 357_492),  // 2064-04-01T17:40Z
        SupermoonEvent(unixTime: 3007478160, distanceKm: 357_060),  // 2065-04-20T18:36Z
        SupermoonEvent(unixTime: 3010010760, distanceKm: 357_701),  // 2065-05-20T02:06Z
        SupermoonEvent(unixTime: 3043189860, distanceKm: 357_347),  // 2066-06-08T02:31Z
        SupermoonEvent(unixTime: 3045720900, distanceKm: 357_985),  // 2066-07-07T09:35Z
        SupermoonEvent(unixTime: 3078899940, distanceKm: 357_244),  // 2067-07-26T09:59Z
        SupermoonEvent(unixTime: 3081430620, distanceKm: 357_783),  // 2067-08-24T16:57Z
        SupermoonEvent(unixTime: 3114609540, distanceKm: 357_038),  // 2068-09-11T17:19Z
        SupermoonEvent(unixTime: 3117145200, distanceKm: 357_770),  // 2068-10-11T01:40Z
        SupermoonEvent(unixTime: 3150329760, distanceKm: 356_888),  // 2069-10-30T03:36Z
        SupermoonEvent(unixTime: 3152871960, distanceKm: 357_913),  // 2069-11-28T13:46Z
        SupermoonEvent(unixTime: 3183514860, distanceKm: 359_832),  // 2070-11-18T05:41Z
        SupermoonEvent(unixTime: 3186057960, distanceKm: 356_466),  // 2070-12-17T16:06Z
        SupermoonEvent(unixTime: 3188601360, distanceKm: 358_080),  // 2071-01-16T02:36Z
        SupermoonEvent(unixTime: 3219243180, distanceKm: 359_264),  // 2072-01-05T18:13Z
        SupermoonEvent(unixTime: 3221787360, distanceKm: 356_549),  // 2072-02-04T04:56Z
        SupermoonEvent(unixTime: 3224330280, distanceKm: 358_773),  // 2072-03-04T15:18Z
        SupermoonEvent(unixTime: 3254974020, distanceKm: 358_976),  // 2073-02-22T07:27Z
        SupermoonEvent(unixTime: 3257515080, distanceKm: 356_722),  // 2073-03-23T17:18Z
        SupermoonEvent(unixTime: 3260051700, distanceKm: 359_152),  // 2073-04-22T01:55Z
        SupermoonEvent(unixTime: 3290697060, distanceKm: 358_695),  // 2074-04-11T18:31Z
        SupermoonEvent(unixTime: 3293230680, distanceKm: 356_818),  // 2074-05-11T02:18Z
        SupermoonEvent(unixTime: 3295762080, distanceKm: 359_375),  // 2074-06-09T09:28Z
        SupermoonEvent(unixTime: 3326409540, distanceKm: 358_893),  // 2075-05-30T02:39Z
        SupermoonEvent(unixTime: 3328940820, distanceKm: 357_104),  // 2075-06-28T09:47Z
        SupermoonEvent(unixTime: 3331472040, distanceKm: 359_587),  // 2075-07-27T16:54Z
        SupermoonEvent(unixTime: 3362119920, distanceKm: 358_826),  // 2076-07-16T10:12Z
        SupermoonEvent(unixTime: 3364650720, distanceKm: 356_919),  // 2076-08-14T17:12Z
        SupermoonEvent(unixTime: 3367183140, distanceKm: 359_382),  // 2076-09-13T00:39Z
        SupermoonEvent(unixTime: 3397829040, distanceKm: 358_570),  // 2077-09-02T17:24Z
        SupermoonEvent(unixTime: 3400363260, distanceKm: 356_765),  // 2077-10-02T01:21Z
        SupermoonEvent(unixTime: 3402902220, distanceKm: 359_572),  // 2077-10-31T10:37Z
        SupermoonEvent(unixTime: 3433546500, distanceKm: 358_350),  // 2078-10-21T02:55Z
        SupermoonEvent(unixTime: 3436087980, distanceKm: 356_716),  // 2078-11-19T12:53Z
        SupermoonEvent(unixTime: 3438632100, distanceKm: 359_943),  // 2078-12-18T23:35Z
        SupermoonEvent(unixTime: 3469274220, distanceKm: 357_702),  // 2079-12-08T15:17Z
        SupermoonEvent(unixTime: 3471817500, distanceKm: 356_570),  // 2080-01-07T01:45Z
        SupermoonEvent(unixTime: 3505003320, distanceKm: 357_444),  // 2081-01-25T04:02Z
        SupermoonEvent(unixTime: 3507546480, distanceKm: 356_979),  // 2081-02-23T14:28Z
        SupermoonEvent(unixTime: 3540732360, distanceKm: 357_400),  // 2082-03-14T16:46Z
        SupermoonEvent(unixTime: 3543270360, distanceKm: 357_275),  // 2082-04-13T01:46Z
        SupermoonEvent(unixTime: 3576450600, distanceKm: 357_335),  // 2083-05-02T02:30Z
        SupermoonEvent(unixTime: 3578982180, distanceKm: 357_437),  // 2083-05-31T09:43Z
        SupermoonEvent(unixTime: 3612160860, distanceKm: 357_594),  // 2084-06-18T10:01Z
        SupermoonEvent(unixTime: 3614691720, distanceKm: 357_671),  // 2084-07-17T17:02Z
        SupermoonEvent(unixTime: 3647871000, distanceKm: 357_442),  // 2085-08-05T17:30Z
        SupermoonEvent(unixTime: 3650402520, distanceKm: 357_437),  // 2085-09-04T00:42Z
        SupermoonEvent(unixTime: 3683582160, distanceKm: 357_193),  // 2086-09-23T01:16Z
        SupermoonEvent(unixTime: 3686119020, distanceKm: 357_417),  // 2086-10-22T09:57Z
        SupermoonEvent(unixTime: 3719304360, distanceKm: 356_998),  // 2087-11-10T12:06Z
        SupermoonEvent(unixTime: 3721847520, distanceKm: 357_557),  // 2087-12-09T22:32Z
        SupermoonEvent(unixTime: 3755033880, distanceKm: 356_557),  // 2088-12-28T00:58Z
        SupermoonEvent(unixTime: 3757577160, distanceKm: 357_727),  // 2089-01-26T11:26Z
        SupermoonEvent(unixTime: 3788219040, distanceKm: 359_788),  // 2090-01-16T03:04Z
        SupermoonEvent(unixTime: 3790762800, distanceKm: 356_642),  // 2090-02-14T13:40Z
        SupermoonEvent(unixTime: 3793304580, distanceKm: 358_386),  // 2090-03-15T23:43Z
        SupermoonEvent(unixTime: 3823948800, distanceKm: 359_508),  // 2091-03-05T16:00Z
        SupermoonEvent(unixTime: 3826488720, distanceKm: 356_790),  // 2091-04-04T01:32Z
        SupermoonEvent(unixTime: 3829024020, distanceKm: 358_699),  // 2091-05-03T09:47Z
        SupermoonEvent(unixTime: 3859669800, distanceKm: 359_240),  // 2092-04-22T02:30Z
        SupermoonEvent(unixTime: 3862202460, distanceKm: 356_856),  // 2092-05-21T10:01Z
        SupermoonEvent(unixTime: 3864733020, distanceKm: 358_868),  // 2092-06-19T16:57Z
        SupermoonEvent(unixTime: 3895380600, distanceKm: 359_433),  // 2093-06-09T10:10Z
        SupermoonEvent(unixTime: 3897911700, distanceKm: 357_100),  // 2093-07-08T17:15Z
        SupermoonEvent(unixTime: 3900443040, distanceKm: 359_037),  // 2093-08-07T00:24Z
        SupermoonEvent(unixTime: 3931090800, distanceKm: 359_323),  // 2094-07-27T17:40Z
        SupermoonEvent(unixTime: 3933622380, distanceKm: 356_868),  // 2094-08-26T00:53Z
        SupermoonEvent(unixTime: 3936155640, distanceKm: 358_821),  // 2094-09-24T08:34Z
        SupermoonEvent(unixTime: 3966801120, distanceKm: 359_015),  // 2095-09-14T01:12Z
        SupermoonEvent(unixTime: 3969336660, distanceKm: 356_687),  // 2095-10-13T09:31Z
        SupermoonEvent(unixTime: 3971876760, distanceKm: 359_027),  // 2095-11-11T19:06Z
        SupermoonEvent(unixTime: 4002520620, distanceKm: 358_732),  // 2096-10-31T11:17Z
        SupermoonEvent(unixTime: 4005063300, distanceKm: 356_614),  // 2096-11-29T21:35Z
        SupermoonEvent(unixTime: 4007607840, distanceKm: 359_407),  // 2096-12-29T08:24Z
        SupermoonEvent(unixTime: 4038249900, distanceKm: 358_044),  // 2097-12-19T00:05Z
        SupermoonEvent(unixTime: 4040793420, distanceKm: 356_464),  // 2098-01-17T10:37Z
        SupermoonEvent(unixTime: 4043336460, distanceKm: 359_873),  // 2098-02-15T21:01Z
        SupermoonEvent(unixTime: 4073979000, distanceKm: 357_789),  // 2099-02-05T12:50Z
        SupermoonEvent(unixTime: 4076521260, distanceKm: 356_861),  // 2099-03-06T23:01Z
        SupermoonEvent(unixTime: 4109706360, distanceKm: 357_742),  // 2100-03-26T01:06Z
        SupermoonEvent(unixTime: 4112243100, distanceKm: 357_109),  // 2100-04-24T09:45Z
    ]

    // MARK: - Major meteor showers (annual)
    // Source: International Meteor Organization major-shower list
    static let meteorShowers: [MeteorShowerEvent] = [
        MeteorShowerEvent(name: "Quadrantids",   peakMonth: 1,  peakDay: 3,  zhr: 120),
        MeteorShowerEvent(name: "Lyrids",        peakMonth: 4,  peakDay: 22, zhr: 18),
        MeteorShowerEvent(name: "Eta Aquariids", peakMonth: 5,  peakDay: 6,  zhr: 50),
        MeteorShowerEvent(name: "Perseids",      peakMonth: 8,  peakDay: 12, zhr: 100),
        MeteorShowerEvent(name: "Orionids",      peakMonth: 10, peakDay: 21, zhr: 20),
        MeteorShowerEvent(name: "Leonids",       peakMonth: 11, peakDay: 17, zhr: 15),
        MeteorShowerEvent(name: "Geminids",      peakMonth: 12, peakDay: 14, zhr: 150),
        MeteorShowerEvent(name: "Ursids",        peakMonth: 12, peakDay: 22, zhr: 10),
    ]

    // MARK: - Types

    struct LunarEclipseEvent {
        let unixTime: Int64
        let type: EclipseType
        let magnitude: Double
        var date: Date { Date(timeIntervalSince1970: TimeInterval(unixTime)) }
    }

    struct SupermoonEvent {
        let unixTime: Int64
        let distanceKm: Int
        var date: Date { Date(timeIntervalSince1970: TimeInterval(unixTime)) }
    }

    struct MeteorShowerEvent {
        let name: String
        let peakMonth: Int
        let peakDay: Int
        let zhr: Int
    }

    enum EclipseType {
        case penumbral, partial, total
    }

    // MARK: - Lookup helpers

    /// Find a lunar eclipse whose date matches the given walk date in the
    /// walker's local calendar. The walk and event dates are compared at
    /// the "start of day" level to match any eclipse happening anywhere
    /// during the walker's local day.
    static func eclipse(on walkDate: Date, calendar: Calendar = .current) -> LunarEclipseEvent? {
        let walkLocalDay = calendar.startOfDay(for: walkDate)
        return lunarEclipses.first { event in
            calendar.startOfDay(for: event.date) == walkLocalDay
        }
    }

    /// Find a supermoon within ±3 days of the walk date, comparing against
    /// the walker's local calendar. The ±3 day window captures walks in
    /// the approach and immediate aftermath of a supermoon full moon.
    static func supermoon(near walkDate: Date, calendar: Calendar = .current) -> SupermoonEvent? {
        let walkLocalDay = calendar.startOfDay(for: walkDate)
        return supermoons.first { event in
            let eventLocalDay = calendar.startOfDay(for: event.date)
            let components = calendar.dateComponents([.day], from: eventLocalDay, to: walkLocalDay)
            let daysBetween = abs(components.day ?? Int.max)
            return daysBetween <= 3
        }
    }

    /// Find a major meteor shower whose peak is within ±1 day of the walk
    /// date (in the walker's local calendar). Matches on (month, day)
    /// rather than year so the annual recurrence works for every year.
    static func meteorShower(on walkDate: Date, calendar: Calendar = .current) -> MeteorShowerEvent? {
        let components = calendar.dateComponents([.month, .day], from: walkDate)
        guard let month = components.month, let day = components.day else { return nil }
        return meteorShowers.first { shower in
            // ±1 day match in (month, day) space. None of our 8 showers peak
            // within 1 day of a month boundary, so we don't need to handle
            // month rollover. (Ursids Dec 22 is the closest to a boundary
            // and still has 2 days of safety.)
            month == shower.peakMonth && abs(day - shower.peakDay) <= 1
        }
    }
}
