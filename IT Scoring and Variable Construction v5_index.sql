/*  Construction of list of Approval ID's used for training testing and Scoring */
/* List of all customers who have only taken one lease */
/* Fraud indicator created */
/*Seasoned indicator Created */
/*warning!!! Leases too recent will appear as fraud and need time to miss payments before being considered as fraud */

-- Change 2/7/2017
--George Hoersting 
--change to score customers that have more than one lease

/*
G. Hoersting - Initial Release
W. Twombly - 9/20/2016 - Added indexes */

        IF OBJECT_ID('tempdb..#lease_list') IS NOT NULL
            DROP TABLE #lease_list

        SELECT  a.ApprovalID ,
                a.TotalPaymentsMade ,
                a.ClientID ,
                b.FirstRentPayment + b.AdditionalDownPayment AS firstrentpayment ,
                CASE WHEN e.StoreType <> ' ' THEN e.StoreType
                     ELSE 'CORE'
                END AS storetype ,
                a.LeaseAddedDate AS origination_date ,
                CASE WHEN a.TotalPaymentsMade <= ( b.FirstRentPayment
                                                   + b.AdditionalDownPayment )
                     THEN 1
                     ELSE 0
                END AS Fraud ,
                CASE WHEN CONVERT(DATE, a.LeaseAddedDate) < ( GETDATE() - 150 )
                     THEN 1
                     ELSE 0
                END AS Seasoned_lease
        INTO    #lease_list
        FROM    rto..WNLI_LeaseView a
                LEFT OUTER JOIN rto..WNLI_leasePeriodInfo b ON a.ApprovalID = b.approvalID
                LEFT OUTER JOIN DataWarehouse..dim_Approval c ON a.ApprovalID = c.ApprovalID
                LEFT OUTER JOIN DataWarehouse..fact_LeaseSum d ON c.ApprovalBKey = d.ApprovalBKey
                LEFT OUTER JOIN DataWarehouse..dim_Store e ON e.StoreBKey = d.StoreBKey
        WHERE   a.ClientID IN ( SELECT  ClientID
                                FROM    rto..WNLI_LeaseView
                                GROUP BY ClientID
                                HAVING  COUNT(ClientID) = 1 )


        CREATE NONCLUSTERED INDEX [IX_#lease_list_approvalid] ON #lease_list
        (
        [ApprovalID] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

/* get lease view attributes */
        IF OBJECT_ID('tempdb..#lease_view_attributes') IS NOT NULL
            DROP TABLE #lease_view_attributes

        SELECT  LeaseID ,
                ClientID ,
                ApprovalID ,
                StoreID ,
                ClientStatus ,
                MonthlyIncome ,
                ClientAddedDate ,
                LeaseAddedDate ,
                LatestFraudDate ,
                LeaseCost ,
                LeaseAmount ,
                PaymentFrequency
        INTO    #lease_view_attributes
        FROM    rto..WNLI_LeaseView
        WHERE   ApprovalID IN ( SELECT  ApprovalID
                                FROM    #lease_list )


        CREATE NONCLUSTERED INDEX [IX_#lease_view_attributes_clientid] ON #lease_view_attributes
        (
        [ClientID] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]


        CREATE NONCLUSTERED INDEX [IX_#lease_view_attributes_storeid] ON #lease_view_attributes
        (
        [StoreID] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]


/* bank attributes*/
/* in the case of new customers this will be accurate*/
/* dedup duplicate active with identical timestamps*/
        IF OBJECT_ID('tempdb..#wnli_bank_attributes') IS NOT NULL
            DROP TABLE #wnli_bank_attributes
        SELECT  *
        INTO    #wnli_bank_attributes
        FROM    ( SELECT    ROW_NUMBER() OVER ( PARTITION BY clientID ORDER BY clientID ) rank ,
                            clientID ,
                            accountType ,
                            debitOrCredit ,
                            routingNumber ,
                            cardName ,
                            primaryPaymentMethod ,
                            CardNumberToken ,
                            expDate ,
                            active ,
                            timeStamp
                  FROM      rto..WNLI_bank
                  WHERE     active = 1
                            AND clientID IN ( SELECT    ClientID
                                              FROM      #lease_view_attributes )
                ) b
        WHERE   b.rank = 1

        CREATE NONCLUSTERED INDEX [IX_#wnli_bank_attributes_clientid] ON #wnli_bank_attributes
        (
        [clientID] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

        CREATE NONCLUSTERED INDEX [IX_#wnli_bank_attributes_cardnumbertoken] ON #wnli_bank_attributes
        (
        [CardNumberToken] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]


/* card appearance */

        IF OBJECT_ID('tempdb..#card_appearance') IS NOT NULL
            DROP TABLE #card_appearance

        SELECT  COUNT(DISTINCT clientID) AS card_appear_number ,
                CardNumberToken AS cardnumber
        INTO    #card_appearance
        FROM    ( SELECT
      DISTINCT          CardNumberToken ,
                            clientID ,
                            expDate
                  FROM      rto..WNLI_bank
                  WHERE     clientID IN ( SELECT    ClientID
                                          FROM      #lease_view_attributes )
                ) b
        GROUP BY CardNumberToken
        HAVING  COUNT(DISTINCT clientID) < 1000 --excludes cards forced to 1000 bin


        CREATE NONCLUSTERED INDEX [IX_#card_appearance_cardnumber] ON #card_appearance
        (
        [cardnumber] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

/* create Store Attributes */
        IF OBJECT_ID('tempdb..#Store_attributes') IS NOT NULL
            DROP TABLE #Store_attributes
        SELECT  storeID ,
                zip ,
                LEFT(zip, 1) AS zipgroup1 ,
                state ,
                city
        INTO    #Store_attributes
        FROM    rto..WNLI_retailStores
        WHERE   storeID IN ( SELECT StoreID
                             FROM   #lease_view_attributes )

/* cart attributes */
        IF OBJECT_ID('tempdb..#cart_attributes') IS NOT NULL
            DROP TABLE #cart_attributes

        SELECT  approvalID ,
                COUNT(DISTINCT SKU) AS distinct_sku_count ,
                COUNT(SKU) AS sku_count ,
                ( COUNT(SKU) - COUNT(DISTINCT SKU) ) AS sku_dif ,
                ( CONVERT(DECIMAL, COUNT(DISTINCT SKU))
                  / ( CONVERT(DECIMAL, COUNT(SKU)) ) ) sku_ratio
        INTO    #cart_attributes
        FROM    rto..WNLI_cart
        GROUP BY approvalID

        CREATE NONCLUSTERED INDEX [IX_#cart_attributes_Approvalid] ON #cart_attributes
        (
        [approvalID] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

/* client attributes */
/* possible lift here from ip adress */


        IF OBJECT_ID('tempdb..#client_attributes') IS NOT NULL
            DROP TABLE #client_attributes

        SELECT  a.clientID ,
                IPAddress ,
                [driversLicense#] ,
                driversLicenseState ,
                DOB ,
                age = DATEDIFF(YEAR, DOB, b.LeaseAddedDate) ,
                timeStamp ,
                firstName ,
                lastName ,
                IdType ,
                LanguagePreference ,
                license_appear_number
        INTO    #client_attributes
        FROM    rto..WNLI_clientInfo a
                LEFT JOIN ( SELECT  [driversLicense#] AS [l_#] ,
                                    COUNT(clientID) AS license_appear_number
                            FROM    rto..WNLI_clientInfo
                            GROUP BY [driversLicense#]
                          ) driver_liscence_count ON [driversLicense#] = [l_#]
                LEFT JOIN #lease_view_attributes b ON b.ClientID = a.clientID

        CREATE NONCLUSTERED INDEX [IX_#client_attributes_Approvalid] ON #client_attributes
        (
        [clientID] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

/* third party fraud attributes */
        IF OBJECT_ID('tempdb..#fp_attributes') IS NOT NULL
            DROP TABLE #fp_attributes


        SELECT  ApprovalID ,
                MAX(FraudScore) AS fraudscore ,
                MAX(CVI) AS cvi ,
                NULLIF(RIGHT('0' + MAX(NAPIndex), 2), '0') AS NAPIndex ,
                NULLIF(RIGHT('0' + MAX(NASIndex), 2), '0') AS NASIndex ,
                MAX(CONVERT(DATE, TimeStamp)) AS fp_timestamp
        INTO    #fp_attributes
        FROM    IntelReports..vwFP_Results
        WHERE   ApprovalID IN ( SELECT  ApprovalID
                                FROM    #lease_list )
        GROUP BY ApprovalID

        CREATE NONCLUSTERED INDEX [IX_#fp_attributes_approvalId] ON #fp_attributes
        (
        [ApprovalID] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

--- This Creates and bins the risk indicators
        IF OBJECT_ID('tempdb..#ln_rsk') IS NOT NULL
            DROP TABLE #ln_rsk

        SELECT  ApprovalID ,
                Riskcode ,
                sequence
        INTO    #ln_rsk
        FROM    ( SELECT    lv.ApprovalID ,
                            Riskcode = ISNULL(ri.RiskCode, 'NONE') ,
                            sequence = ROW_NUMBER() OVER ( PARTITION BY lv.ApprovalID,
                                                           ISNULL(ri.RiskCode,
                                                              'NONE') ORDER BY lv.ApprovalID, ISNULL(ri.RiskCode,
                                                              'NONE') )
                  FROM      rto..WNLI_LeaseView lv
                            LEFT JOIN IntelReports..FP_Applicant a ON a.ApprovalID = lv.ApprovalID
                            LEFT JOIN IntelReports..FP_RiskIndicators ri ON a.ApplicantID = ri.ApplicantID
                  WHERE     a.ApplicantID >= 1
                ) a
        WHERE   a.sequence = 1

-- check dedup use on subquery
    --select count(*)  from #ln_rsk where sequence =1

-- identical to
           --select count(*) from #ln_rsk group by approvalid,riskcode

        DECLARE @pivcol AS NVARCHAR(MAX) ,
            @query AS NVARCHAR(MAX) ,
            @colname AS NVARCHAR(MAX);
        SET @pivcol = STUFF((SELECT DISTINCT
                                    ',' + QUOTENAME('_MC_v2_' + c.Riskcode)
                             FROM   #ln_rsk c
            FOR             XML PATH('') ,
                                TYPE
            ).value('.', 'NVARCHAR(MAX)'), 1, 1, '')


        SET @colname = STUFF((SELECT DISTINCT
                                        ', isnull(' + QUOTENAME('_MC_v2_'
                                                              + c.Riskcode)
                                        + ',1) as' + QUOTENAME('_MC_v2_'
                                                              + c.Riskcode)
                              FROM      #ln_rsk c
            FOR              XML PATH('') ,
                                 TYPE
            ).value('.', 'NVARCHAR(MAX)'), 1, 1, '')

        SET @query = 'drop table ##risk_indicators SELECT approvalid as appid, '
            + @colname + '
      into ##risk_indicators
      from
            (
                select approvalid
                    , ''_MC_v2_'' + riskcode as riskcode, ''0'' as sequence

                from #ln_rsk
           ) x
            pivot
            (
                 min(sequence)

                for riskcode in (' + @pivcol + ')
            ) p  order by approvalid'

-- create table ##risk_indicators
        EXECUTE(@query)

-- add sum

        CREATE NONCLUSTERED INDEX [IX_#ln_rsk_approvalId] ON #ln_rsk
        (
        [ApprovalID] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

        IF OBJECT_ID('tempdb..#riskindicators ') IS NOT NULL
            DROP TABLE #riskindicators

        SELECT  a.* ,
                b.sequence AS _mc_v2_z_sum
        INTO    #riskindicators
        FROM    ##risk_indicators a
                LEFT JOIN ( SELECT  ApprovalID ,
                                    SUM(sequence) AS sequence
                            FROM    #ln_rsk
                            GROUP BY ApprovalID
                          ) b ON a.appid = b.ApprovalID

        CREATE NONCLUSTERED INDEX [IX_#riskindicators_appid] ON #riskindicators
        (
        [appid] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

/* get max approval amount*/
        IF OBJECT_ID('tempdb..#max_approval') IS NOT NULL
            DROP TABLE #max_approval

        SELECT  approvalID ,
                approvalAmount
        INTO    #max_approval
        FROM    rto..WNLI_approval
        WHERE   approvalID IN ( SELECT  ApprovalID
                                FROM    #lease_list )

        CREATE NONCLUSTERED INDEX [IX_#max_approval_approvalId] ON #max_approval
        (
        [approvalID] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

/* get what payment types present at time of origination*/
        IF OBJECT_ID('tempdb..#ach_credit_indicator') IS NOT NULL
            DROP TABLE #ach_credit_indicator

        SELECT  a.ClientID ,
                SUM(CASE WHEN b.primaryPaymentMethod = 'ACH'
                              AND CONVERT(DATE, a.LeaseAddedDate) = CONVERT(DATE, b.timeStamp)
                         THEN 1
                         ELSE 0
                    END) AS ach_orig ,
                SUM(CASE WHEN b.primaryPaymentMethod = 'CreditCard'
                              AND CONVERT(DATE, a.LeaseAddedDate) = CONVERT(DATE, b.timeStamp)
                         THEN 1
                         ELSE 0
                    END) AS cc_orig
        INTO    #ach_credit_indicator
        FROM    #lease_view_attributes a
                LEFT JOIN rto..WNLI_bank b ON a.ClientID = b.clientID
        GROUP BY a.ClientID

        CREATE NONCLUSTERED INDEX [IX_#ach_credit_indicatorl_clientid] ON #ach_credit_indicator
        (
        [ClientID] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

/* store age */
        IF OBJECT_ID('tempdb..#store_inception_date') IS NOT NULL
            DROP TABLE #store_inception_date

        SELECT  StoreID ,
                MIN(CONVERT(DATE, LeaseAddedDate)) AS st_inception_date
        INTO    #store_inception_date
        FROM    rto..WNLI_LeaseView
        GROUP BY StoreID



/*customer zip for distance*/
        IF OBJECT_ID('tempdb..#customer_zip0') IS NOT NULL
            DROP TABLE #customer_zip0

        SELECT  p.clientID ,
                SUBSTRING(p.zip, 1, 5) AS customer_zip
/*zipcitydistance(substr(s.zip,1,5),substr(p.zip,1,5)) as distance*/
        INTO    #customer_zip0
        FROM    rto..WNLI_address AS p
        WHERE   p.active = 1

        CREATE NONCLUSTERED INDEX [IX_#customer_zip0_clientid] ON #customer_zip0
        (
        [clientID] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

-- dedup customer zip
        IF OBJECT_ID('tempdb..#customer_zip') IS NOT NULL
            DROP TABLE #customer_zip
        SELECT  clientID ,
                customer_zip
        INTO    #customer_zip
        FROM    ( SELECT    clientID ,
                            customer_zip ,
                            seq = ROW_NUMBER() OVER ( PARTITION BY clientID ORDER BY clientID )
                  FROM      #customer_zip0
                ) b
        WHERE   seq = 1

        CREATE NONCLUSTERED INDEX [IX_#customer_zip_clientid] ON #customer_zip
        (
        [clientID] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]


/* lattitude longitude*/
        IF OBJECT_ID('tempdb..#lat_long') IS NOT NULL
        DROP TABLE #lat_long
        SELECT  zip zipkey ,
                latitude ,
                longitude
        INTO    #lat_long
        FROM    rto..WNLI_ZipCodes


/* join all attributes */

/* Join all model attributes */
        IF OBJECT_ID('tempdb..#Fraud_master') IS NOT NULL
            DROP TABLE #Fraud_master
        SELECT  ISNULL(_mc_v2_z_sum, 1) AS _mc_v2_z_sum ,
                ll.origination_date ,
                ll.storetype ,
                ll.Fraud ,
                ll.Seasoned_lease ,
                lvatt.LeaseID ,
                lvatt.ClientID ,
                lvatt.ApprovalID ,
                lvatt.StoreID ,
                lvatt.ClientStatus ,
                lvatt.MonthlyIncome ,
                lvatt.ClientAddedDate ,
                lvatt.LeaseAddedDate ,
                lvatt.LatestFraudDate ,
                lvatt.LeaseCost ,
                lvatt.LeaseAmount ,
                lvatt.PaymentFrequency ,
                wbatt.accountType ,
                wbatt.debitOrCredit ,
                wbatt.routingNumber ,
                wbatt.cardName ,
                wbatt.primaryPaymentMethod ,
                wbatt.CardNumberToken ,
                wbatt.expDate ,
                cart.distinct_sku_count ,
                cart.sku_count ,
                cart.sku_ratio ,
                cart.sku_dif ,
                cap.card_appear_number ,
                catt.IPAddress ,
                catt.[driversLicense#] ,
                catt.driversLicenseState ,
                catt.firstName ,
                catt.lastName ,
                catt.age ,
                catt.IdType ,
                catt.LanguagePreference ,
                catt.license_appear_number ,
                sa.zip ,
                sa.zipgroup1 ,
                sa.state ,
                sa.city ,
                fp.fraudscore ,
                fp.cvi ,
                fp.NASIndex ,
                fp.NAPIndex ,
                fp.fp_timestamp ,
                mapp.approvalAmount ,
                aci.ach_orig ,
                aci.cc_orig ,
                czip.customer_zip ,
                storedate.st_inception_date ,
                geostore.latitude store_lat ,
                geostore.longitude store_long ,
                geocus.latitude cus_lat ,
                geocus.longitude cus_long ,
                ISNULL(_MC_v2_16, 1) AS _MC_v2_16 ,
                ISNULL(_MC_v2_74, 1) AS _MC_v2_74 ,
                ISNULL(_MC_v2_76, 1) AS _MC_v2_76 ,
                ISNULL(_MC_v2_CO, 1) AS _MC_v2_CO ,
                ISNULL(_MC_v2_27, 1) AS _MC_v2_27 ,
                ISNULL(_MC_v2_31, 1) AS _MC_v2_31 ,
                ISNULL(_MC_v2_50, 1) AS _MC_v2_50 ,
                ISNULL(_MC_v2_80, 1) AS _MC_v2_80 ,
                ISNULL(_MC_v2_85, 1) AS _MC_v2_85 ,
                ISNULL(_MC_v2_MS, 1) AS _MC_v2_MS ,
                ISNULL(_MC_v2_PO, 1) AS _MC_v2_PO ,
                ISNULL(_MC_v2_VA, 1) AS _MC_v2_VA ,
                ISNULL(_MC_v2_ZI, 1) AS _MC_v2_ZI ,
                ISNULL(_MC_v2_07, 1) AS _MC_v2_07 ,
                ISNULL(_MC_v2_12, 1) AS _MC_v2_12 ,
                ISNULL(_MC_v2_38, 1) AS _MC_v2_38 ,
                ISNULL(_MC_v2_72, 1) AS _MC_v2_72 ,
                ISNULL(_MC_v2_73, 1) AS _MC_v2_73 ,
                ISNULL(_MC_v2_9K, 1) AS _MC_v2_9K ,
                ISNULL(_MC_v2_FQ, 1) AS _MC_v2_FQ ,
                ISNULL(_MC_v2_IS, 1) AS _MC_v2_IS ,
                ISNULL(_MC_v2_IT, 1) AS _MC_v2_IT ,
                ISNULL(_MC_v2_MN, 1) AS _MC_v2_MN ,
                ISNULL(_MC_v2_08, 1) AS _MC_v2_08 ,
                ISNULL(_MC_v2_30, 1) AS _MC_v2_30 ,
                ISNULL(_MC_v2_40, 1) AS _MC_v2_40 ,
                ISNULL(_MC_v2_64, 1) AS _MC_v2_64 ,
                ISNULL(_MC_v2_66, 1) AS _MC_v2_66 ,
                ISNULL(_MC_v2_CA, 1) AS _MC_v2_CA ,
                ISNULL(_MC_v2_NF, 1) AS _MC_v2_NF ,
                ISNULL(_MC_v2_RS, 1) AS _MC_v2_RS ,
                ISNULL(_MC_v2_WL, 1) AS _MC_v2_WL ,
                ISNULL(_MC_v2_10, 1) AS _MC_v2_10 ,
                ISNULL(_MC_v2_15, 1) AS _MC_v2_15 ,
                ISNULL(_MC_v2_28, 1) AS _MC_v2_28 ,
                ISNULL(_MC_v2_44, 1) AS _MC_v2_44 ,
                ISNULL(_MC_v2_49, 1) AS _MC_v2_49 ,
                ISNULL(_MC_v2_51, 1) AS _MC_v2_51 ,
                ISNULL(_MC_v2_75, 1) AS _MC_v2_75 ,
                ISNULL(_MC_v2_9D, 1) AS _MC_v2_9D ,
                ISNULL(_MC_v2_BO, 1) AS _MC_v2_BO ,
                ISNULL(_MC_v2_CL, 1) AS _MC_v2_CL ,
                ISNULL(_MC_v2_CZ, 1) AS _MC_v2_CZ ,
                ISNULL(_MC_v2_DI, 1) AS _MC_v2_DI ,
                ISNULL(_MC_v2_MI, 1) AS _MC_v2_MI ,
                ISNULL(_MC_v2_02, 1) AS _MC_v2_02 ,
                ISNULL(_MC_v2_03, 1) AS _MC_v2_03 ,
                ISNULL(_MC_v2_26, 1) AS _MC_v2_26 ,
                ISNULL(_MC_v2_29, 1) AS _MC_v2_29 ,
                ISNULL(_MC_v2_37, 1) AS _MC_v2_37 ,
                ISNULL(_MC_v2_48, 1) AS _MC_v2_48 ,
                ISNULL(_MC_v2_52, 1) AS _MC_v2_52 ,
                ISNULL(_MC_v2_82, 1) AS _MC_v2_82 ,
                ISNULL(_MC_v2_FV, 1) AS _MC_v2_FV ,
                ISNULL(_MC_v2_04, 1) AS _MC_v2_04 ,
                ISNULL(_MC_v2_06, 1) AS _MC_v2_06 ,
                ISNULL(_MC_v2_09, 1) AS _MC_v2_09 ,
                ISNULL(_MC_v2_14, 1) AS _MC_v2_14 ,
                ISNULL(_MC_v2_19, 1) AS _MC_v2_19 ,
                ISNULL(_MC_v2_25, 1) AS _MC_v2_25 ,
                ISNULL(_MC_v2_89, 1) AS _MC_v2_89 ,
                ISNULL(_MC_v2_PA, 1) AS _MC_v2_PA ,
                ISNULL(_MC_v2_11, 1) AS _MC_v2_11 ,
                ISNULL(_MC_v2_34, 1) AS _MC_v2_34 ,
                ISNULL(_MC_v2_71, 1) AS _MC_v2_71 ,
                ISNULL(_MC_v2_90, 1) AS _MC_v2_90 ,
                ISNULL(_MC_v2_MO, 1) AS _MC_v2_MO ,
                ISNULL(_MC_v2_NB, 1) AS _MC_v2_NB ,
                ISNULL(_MC_v2_SD, 1) AS _MC_v2_SD ,
                ISNULL(_MC_v2_SR, 1) AS _MC_v2_SR ,
          --isnull(_mc_v2_NO,1) as _MC_v2_NONE,
                CASE WHEN _mc_v2_no IS NULL THEN 1
                     WHEN _mc_v2_no = 1 THEN 0
                     WHEN _mc_v2_no = 0 THEN 1
                END AS _MC_v2_NONE ,

        /* calculated */
                storeage = DATEDIFF(MONTH, storedate.st_inception_date,
                                    lvatt.LeaseAddedDate) ,
                seasonality = MONTH(ll.origination_date) ,
                state_flag = CASE WHEN catt.driversLicenseState <> sa.state
                                  THEN 1
                                  ELSE 0
                             END ,
                online = ( CASE WHEN lvatt.ApprovalID IN (
                                     SELECT approvalID
                                     FROM   IntelReports..DecisionSystem
                                     WHERE  storeNumber IN ( '1000', '1001',
                                                             '1002', '1003',
                                                             '1004' ) ) THEN 1
                                ELSE 0
                           END ) ,
                add_flag = CASE WHEN lvatt.LeaseCost - lvatt.LeaseAmount > 100
                                THEN 1
                                ELSE 0
                           END ,
                ltc = lvatt.LeaseAmount / NULLIF(mapp.approvalAmount, 0) ,
                lease_yyyymm = CAST(YEAR(ll.origination_date) AS VARCHAR(4))
                + RIGHT('0' + CAST(MONTH(ll.origination_date) AS VARCHAR(2)),
                        2)
        INTO    #Fraud_master
        FROM    #lease_list ll
                LEFT JOIN #lease_view_attributes lvatt ON ll.ApprovalID = lvatt.ApprovalID
                LEFT JOIN #wnli_bank_attributes wbatt ON lvatt.ClientID = wbatt.clientID
                LEFT JOIN #cart_attributes cart ON ll.ApprovalID = cart.approvalID
                LEFT JOIN #card_appearance cap ON wbatt.CardNumberToken = cap.cardnumber
                LEFT JOIN #client_attributes catt ON lvatt.ClientID = catt.clientID
                LEFT JOIN #Store_attributes sa ON lvatt.StoreID = sa.storeID
                LEFT JOIN #fp_attributes fp ON fp.ApprovalID = ll.ApprovalID
                LEFT JOIN #max_approval mapp ON mapp.approvalID = ll.ApprovalID
                LEFT JOIN #ach_credit_indicator aci ON lvatt.ClientID = aci.ClientID
/* begin new */
                LEFT JOIN #customer_zip czip ON lvatt.ClientID = czip.clientID
                LEFT JOIN #store_inception_date storedate ON storedate.StoreID = lvatt.StoreID
                LEFT JOIN #riskindicators ri ON ri.appid = ll.ApprovalID
                LEFT JOIN #lat_long geocus ON geocus.zipkey = czip.customer_zip
                LEFT JOIN #lat_long geostore ON geostore.zipkey = sa.zip

-- calculate distance to store
--convert to radians
        IF OBJECT_ID('tempdb..#dtest0') IS NOT NULL
        DROP TABLE #dtest0
        SELECT  clong = ATAN(1) / 45 * cus_long ,
                clat = ATAN(1) / 45 * cus_lat ,
                slong = ATAN(1) / 45 * store_long ,
                slat = ATAN(1) / 45 * store_lat ,
                *
        INTO    #dtest0
        FROM    #Fraud_master
--- create distance multiplier from radians
        IF OBJECT_ID('tempdb..#dtest') IS NOT NULL
            DROP TABLE #dtest
        SELECT
 -- Distance=     acos(SIN(RADIANS(CONVERT(DEC,STORE_LAT)))*SIN(RADIANS(CONVERT(DEC,CUS_LAT))) + COS(RADIANS(CONVERT(DEC,STORE_LAT)))*COS(RADIANS(CONVERT(DEC,CUS_LAT)))*COS(RADIANS(CONVERT(DEC,CUS_LONG))-RADIANS(CONVERT(DEC,STORE_LONG))))*6371000/1609.34,*
--d= ((Sin((convert(dec,store_lat)/57.2958)) * Sin((convert(dec,cus_lat)/57.2958))) + (Cos((convert(dec,store_lat)/57.2958)) * Cos((convert(dec,cus_lat)/57.2958)) * Cos((convert(dec,cus_long)/57.2958) - (convert(dec,store_long)/57.2958))))
  --distance = sin((RADIANS(CONVERT(DEC,CUS_LAT)) -  RADIANS(CONVERT(DEC,STORE_LAT)))/2)*sin( (RADIANS(CONVERT(DEC,CUS_LAT)) -  RADIANS(CONVERT(DEC,STORE_LAT)))/2)+cos(RADIANS(CONVERT(DEC,CUS_LAT))) * cos(RADIANS(CONVERT(DEC,store_LAT)))* sin( (RADIANS(CONVERT(DEC,CUS_Long)) -  RADIANS(CONVERT(DEC,STORE_Long)))/2)*sin( (RADIANS(CONVERT(DEC,CUS_Long)) -  RADIANS(CONVERT(DEC,STORE_Long)))/2),*
                d = CASE WHEN ( SIN(slat) * SIN(clat) + COS(slat) * COS(clat)
                                * COS(slong - clong) ) > 1 THEN 1
                         ELSE ( SIN(slat) * SIN(clat) + COS(slat) * COS(clat)
                                * COS(slong - clong) )
                    END ,
                *
        INTO    #dtest
        FROM    #dtest0


        IF OBJECT_ID('tempdb..#fraud_master2') IS NOT NULL
        DROP TABLE #fraud_master2
        SELECT  distance = 3949.99 * ACOS(d) ,
                *
        INTO    #fraud_master2
        FROM    #dtest


/* Bin the data in Fraud master */
/* categorical vairiables begin with prefix _MC */
/*Continuous Variables Begin with Prefix  _M */
/* _MY_Fraud is the Response */

        IF OBJECT_ID('tempdb..#Bin_Fraud_master') IS NOT NULL
            DROP TABLE #Bin_Fraud_master

        SELECT  * ,
                _my_fraud = Fraud ,
                _mc_online = online ,
                _m_monthlyincome_1 = MonthlyIncome ,
                _mc_add_flag = add_flag ,
                _mc_paymentfrequency = PaymentFrequency ,
                _mc_seasonality = seasonality ,
                _mc_state_flag = state_flag ,
                _mc_zipgroup1 = zipgroup1 ,
                _m_age_1 = age ,
                _m_ltc_1 = ltc ,
                _mc_primarypaymentmethod = ( CASE WHEN primaryPaymentMethod IS NOT NULL
                                                       AND primaryPaymentMethod <> ''
                                                  THEN primaryPaymentMethod
                                                  ELSE 'CreditCard'
                                             END ) ,
                _mc_card_appear_number = ( CASE WHEN card_appear_number IS NULL
                                                THEN 0
                                                WHEN card_appear_number = 1
                                                THEN 1
                                                WHEN card_appear_number = 2
                                                THEN 2
                                                WHEN card_appear_number >= 3
                                                THEN 3
                                                ELSE 0
                                           END ) ,
                _mc_storetype = ( CASE WHEN storetype IN ( 'FLS', 'AUTO' )
                                       THEN 'FLSAUTO'
                                       ELSE storetype
                                  END ) ,
                _mc_sku_dif = ( CASE WHEN sku_dif = 0
                                          OR sku_dif IS NULL THEN 0
                                     WHEN sku_dif = 1 THEN 1
                                     WHEN sku_dif >= 2 THEN 2
                                END ) ,
                _mc_languagepreference = ( CASE WHEN LanguagePreference IS NULL
                                                THEN 4
                                                WHEN LanguagePreference = 0
                                                THEN 0
                                                WHEN LanguagePreference = 1
                                                THEN 1
                                                WHEN LanguagePreference = 2
                                                THEN 2
                                                WHEN LanguagePreference = 3
                                                THEN 3
                                           END ) ,
                _mc_idtype = ( CASE WHEN IdType IS NULL
                                         OR IdType = '' THEN 'missing'
                                    ELSE IdType
                               END ) ,
                _mc_cc_orig = ( CASE WHEN cc_orig = 0 THEN 0
                                     WHEN cc_orig = 1 THEN 1
                                     WHEN cc_orig >= 2 THEN 2
                                END ) ,
                _mc_nas = ( CASE WHEN NASIndex IS NULL THEN 'missing'
                                 ELSE NASIndex
                            END ) ,
                _mc_nap = ( CASE WHEN NAPIndex IS NULL THEN 'missing'
                                 ELSE NAPIndex
                            END ) ,
                _mc_cvi = ( CASE WHEN cvi IS NOT NULL
                                      AND cvi <> '' THEN cvi
                                 ELSE 'missing'
                            END ) ,
                _mcfp_quintile = ( CASE WHEN fp_timestamp < '2015-04-01'
                                             AND ( fraudscore BETWEEN 0 AND 608 )
                                        THEN 1
                                        WHEN fp_timestamp < '2015-04-01'
                                             AND ( fraudscore BETWEEN 609 AND 659 )
                                        THEN 2
                                        WHEN fp_timestamp < '2015-04-01'
                                             AND ( fraudscore BETWEEN 660 AND 699 )
                                        THEN 3
                                        WHEN fp_timestamp < '2015-04-01'
                                             AND ( fraudscore BETWEEN 700 AND 741 )
                                        THEN 4
                                        WHEN fp_timestamp < '2015-04-01'
                                             AND ( fraudscore > 741 ) THEN 5
                                        WHEN fp_timestamp >= '2015-04-01'
                                             AND ( fraudscore BETWEEN 0 AND 652 )
                                        THEN 1
                                        WHEN fp_timestamp >= '2015-04-01'
                                             AND ( fraudscore BETWEEN 653 AND 706 )
                                        THEN 2
                                        WHEN fp_timestamp >= '2015-04-01'
                                             AND ( fraudscore BETWEEN 707 AND 747 )
                                        THEN 3
                                        WHEN fp_timestamp >= '2015-04-01'
                                             AND ( fraudscore BETWEEN 748 AND 790 )
                                        THEN 4
                                        WHEN fp_timestamp >= '2015-04-01'
                                             AND ( fraudscore > 790 ) THEN 5
                                        ELSE 4
                                   END ) ,
                _mc_sage_orig = ( CASE WHEN ROUND(storeage, 0) <= 1 THEN 1
                                       WHEN ROUND(storeage, 0) BETWEEN 2 AND 3
                                       THEN 2
                                       WHEN ROUND(storeage, 0) BETWEEN 4 AND 10
                                       THEN 3
                                       WHEN ROUND(storeage, 0) BETWEEN 11 AND 20
                                       THEN 4
                                       WHEN ROUND(storeage, 0) > 20 THEN 5
                                       ELSE 6
                                  END ) ,
                _mc_sdistance = ( CASE WHEN ROUND(distance, 0) <= 25 THEN 1
                                       WHEN ROUND(distance, 0) BETWEEN 26 AND 50
                                       THEN 2
                                       WHEN ROUND(distance, 0) BETWEEN 51 AND 75
                                       THEN 3
                                       WHEN ROUND(distance, 0) BETWEEN 76 AND 100
                                       THEN 4
                                       WHEN ROUND(distance, 0) BETWEEN 101 AND 500
                                       THEN 5
                                       WHEN ROUND(distance, 0) > 500 THEN 6
                                       ELSE 7
                                  END )
        INTO    #bin_fraud_master
        FROM    #fraud_master2


        IF OBJECT_ID('tempdb..#core_pre_scoring') IS NOT NULL
        DROP TABLE #core_pre_scoring
        SELECT  a.* ,
                b.*
        INTO    #core_pre_scoring
        FROM    #bin_fraud_master a
                CROSS JOIN ( SELECT *
                             FROM   analytics..orig_parameter_coef_v2
                             WHERE  model = 'CORE_MODEL'
                           ) b
        WHERE   a.storetype = 'CORE'





/* samll issues resulting in 42 nulls out of 600,000*/
/*ltc issue */ /* no biweekly for core training data*/
/*-------------------------Begin Code for Scoring core  */

                    /*intercept*/

        IF OBJECT_ID('tempdb..#core_score') IS NOT NULL
        DROP TABLE #core_score
        SELECT  b.* ,
                probability = b.z / ( 1 + b.z )
        INTO    #core_score
        FROM    ( SELECT    z = EXP(intercept
                                    + ( CASE WHEN _mc_online = 0
                                             THEN _mc_online0
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_add_flag = 0
                                             THEN _mc_add_flag0
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_paymentfrequency = '14 Day'
                                             THEN _mc_paymentfrequency14_day
                                             WHEN _mc_paymentfrequency = '28 Day'
                                             THEN _mc_paymentfrequency28_day
                                             WHEN _mc_paymentfrequency = 'bi-weekly'
                                             THEN _mc_paymentfrequency14_day
                                             WHEN _mc_paymentfrequency = 'Monthly'
                                             THEN 0
                                        END )
                                    + ( CASE WHEN _mc_primarypaymentmethod = 'ACH'
                                             THEN _mc_primarypaymentmethodACH
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_seasonality = 1
                                             THEN _mc_seasonality1
                                             WHEN _mc_seasonality = 2
                                             THEN _mc_seasonality2
                                             WHEN _mc_seasonality = 3
                                             THEN _mc_seasonality3
                                             WHEN _mc_seasonality = 4
                                             THEN _mc_seasonality4
                                             WHEN _mc_seasonality = 5
                                             THEN _mc_seasonality5
                                             WHEN _mc_seasonality = 6
                                             THEN _mc_seasonality6
                                             WHEN _mc_seasonality = 7
                                             THEN _mc_seasonality7
                                             WHEN _mc_seasonality = 8
                                             THEN _mc_seasonality8
                                             WHEN _mc_seasonality = 9
                                             THEN _mc_seasonality9
                                             WHEN _mc_seasonality = 10
                                             THEN _mc_seasonality10
                                             WHEN _mc_seasonality = 11
                                             THEN _mc_seasonality11
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_zipgroup1 = '0'
                                             THEN _mc_zipgroup10
                                             WHEN _mc_zipgroup1 = '1'
                                             THEN _mc_zipgroup11
                                             WHEN _mc_zipgroup1 = '2'
                                             THEN _mc_zipgroup12
                                             WHEN _mc_zipgroup1 = '3'
                                             THEN _mc_zipgroup13
                                             WHEN _mc_zipgroup1 = '4'
                                             THEN _mc_zipgroup14
                                             WHEN _mc_zipgroup1 = '5'
                                             THEN _mc_zipgroup15
                                             WHEN _mc_zipgroup1 = '6'
                                             THEN _mc_zipgroup16
                                             WHEN _mc_zipgroup1 = '7'
                                             THEN _mc_zipgroup17
                                             WHEN _mc_zipgroup1 = '8'
                                             THEN _mc_zipgroup18
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_card_appear_number = 0
                                             THEN _mc_card_appear_number0
                                             WHEN _mc_card_appear_number = 1
                                             THEN _mc_card_appear_number1
                                             WHEN _mc_card_appear_number = 2
                                             THEN _mc_card_appear_number2
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_sku_dif = 0
                                             THEN _mc_sku_dif0
                                             WHEN _mc_sku_dif = 1
                                             THEN _mc_sku_dif1
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_languagepreference = 0
                                             THEN _mc_languagepreference0
                                             WHEN _mc_languagepreference = 1
                                             THEN _mc_languagepreference1
                                             WHEN _mc_languagepreference = 2
                                             THEN _mc_languagepreference2
                                             WHEN _mc_languagepreference = 3
                                             THEN _mc_languagepreference3
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_idtype = 'Drivers License'
                                             THEN _mc_idtypeDrivers_License
                                             WHEN _mc_idtype = 'Green Card'
                                             THEN _mc_idtypeGreen_Card
                                             WHEN _mc_idtype = 'Military ID'
                                             THEN _mc_idtypeMilitary_ID
                                             WHEN _mc_idtype = 'Missing'
                                             THEN _mc_idtypeMissing
                                             WHEN _mc_idtype = 'Passport'
                                             THEN _mc_idtypePassport
                                             WHEN _mc_idtype = 'State ID'
                                             THEN _mc_idtypeState_ID
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mcfp_quintile = 1
                                             THEN _mcfp_quintile1
                                             WHEN _mcfp_quintile = 2
                                             THEN _mcfp_quintile2
                                             WHEN _mcfp_quintile = 3
                                             THEN _mcfp_quintile3
                                             WHEN _mcfp_quintile = 4
                                             THEN _mcfp_quintile4
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_cc_orig = 0
                                             THEN _mc_cc_orig0
                                             WHEN _mc_cc_orig = 1
                                             THEN _mc_cc_orig1
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_nas = '00' THEN _mc_nas0
                                             WHEN _mc_nas = '01' THEN _mc_nas1
                                             WHEN _mc_nas = '02' THEN _mc_nas2
                                             WHEN _mc_nas = '03' THEN _mc_nas3
                                             WHEN _mc_nas = '04' THEN _mc_nas4
                                             WHEN _mc_nas = '05' THEN _mc_nas5
                                             WHEN _mc_nas = '06' THEN _mc_nas6
                                             WHEN _mc_nas = '07' THEN _mc_nas7
                                             WHEN _mc_nas = '08' THEN _mc_nas8
                                             WHEN _mc_nas = '09' THEN _mc_nas9
                                             WHEN _mc_nas = '10'
                                             THEN _mc_nas10
                                             WHEN _mc_nas = '11'
                                             THEN _mc_nas11
                                             WHEN _mc_nas = '12'
                                             THEN _mc_nas12
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_cvi = '0' THEN _mc_cvi0
                                             WHEN _mc_cvi = '10'
                                             THEN _mc_cvi10
                                             WHEN _mc_cvi = '20'
                                             THEN _mc_cvi20
                                             WHEN _mc_cvi = '30'
                                             THEN _mc_cvi30
                                             WHEN _mc_cvi = '40'
                                             THEN _mc_cvi40
                                             WHEN _mc_cvi = '50'
                                             THEN _mc_cvi50
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_sdistance = 1
                                             THEN _mc_sdistance1
                                             WHEN _mc_sdistance = 2
                                             THEN _mc_sdistance2
                                             WHEN _mc_sdistance = 3
                                             THEN _mc_sdistance3
                                             WHEN _mc_sdistance = 4
                                             THEN _mc_sdistance4
                                             WHEN _mc_sdistance = 5
                                             THEN _mc_sdistance5
                                             WHEN _mc_sdistance = 6
                                             THEN _mc_sdistance6
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_sage_orig = 1
                                             THEN _mc_sage_orig1
                                             WHEN _mc_sage_orig = 2
                                             THEN _mc_sage_orig2
                                             WHEN _mc_sage_orig = 3
                                             THEN _mc_sage_orig3
                                             WHEN _mc_sage_orig = 4
                                             THEN _mc_sage_orig4
                                             ELSE 0
                                        END ) + ISNULL(_MC_v2_16, 0)
                                    * ISNULL(_MC_v2_160, 0) + ISNULL(_MC_v2_04,
                                                              0)
                                    * ISNULL(_MC_v2_040, 0) + ISNULL(_MC_v2_40,
                                                              0)
                                    * ISNULL(_MC_v2_400, 0) + ISNULL(_MC_v2_31,
                                                              0)
                                    * ISNULL(_MC_v2_310, 0) + ISNULL(_MC_v2_38,
                                                              0)
                                    * ISNULL(_MC_v2_380, 0) + ISNULL(_MC_v2_37,
                                                              0)
                                    * ISNULL(_MC_v2_370, 0) + ISNULL(_MC_v2_49,
                                                              0)
                                    * ISNULL(_MC_v2_490, 0) + ISNULL(_MC_v2_14,
                                                              0)
                                    * ISNULL(_MC_v2_140, 0) + ISNULL(_MC_v2_DI,
                                                              0)
                                    * ISNULL(_MC_v2_DI0, 0) + ISNULL(_MC_v2_RS,
                                                              0)
                                    * ISNULL(_MC_v2_RS0, 0) + ISNULL(_MC_v2_MO,
                                                              0)
                                    * ISNULL(_MC_v2_MO0, 0) + ISNULL(_MC_v2_PA,
                                                              0)
                                    * ISNULL(_MC_v2_PA0, 0) + ISNULL(_MC_v2_ZI,
                                                              0)
                                    * ISNULL(_MC_v2_ZI0, 0) + ISNULL(_MC_v2_74,
                                                              0)
                                    * ISNULL(_MC_v2_740, 0) + ISNULL(_MC_v2_28,
                                                              0)
                                    * ISNULL(_MC_v2_280, 0) + ISNULL(_MC_v2_08,
                                                              0)
                                    * ISNULL(_MC_v2_080, 0) + ISNULL(_MC_v2_52,
                                                              0)
                                    * ISNULL(_MC_v2_520, 0) + ISNULL(_MC_v2_89,
                                                              0)
                                    * ISNULL(_MC_v2_890, 0) + ISNULL(_MC_v2_MN,
                                                              0)
                                    * ISNULL(_MC_v2_MN0, 0) + ISNULL(_MC_v2_02,
                                                              0)
                                    * ISNULL(_MC_v2_020, 0) + ISNULL(_MC_v2_75,
                                                              0)
                                    * ISNULL(_MC_v2_750, 0) + ISNULL(_MC_v2_MI,
                                                              0)
                                    * ISNULL(_MC_v2_MI0, 0) + ISNULL(_MC_v2_73,
                                                              0)
                                    * ISNULL(_MC_v2_730, 0) + ISNULL(_MC_v2_29,
                                                              0)
                                    * ISNULL(_MC_v2_290, 0) + ISNULL(_MC_v2_IS,
                                                              0)
                                    * ISNULL(_MC_v2_IS0, 0) + ISNULL(_MC_v2_19,
                                                              0)
                                    * ISNULL(_MC_v2_190, 0) + ISNULL(_MC_v2_BO,
                                                              0)
                                    * ISNULL(_MC_v2_BO0, 0) + ISNULL(_MC_v2_85,
                                                              0)
                                    * ISNULL(_MC_v2_850, 0) + ISNULL(_MC_v2_9D,
                                                              0)
                                    * ISNULL(_MC_v2_9D0, 0) + ISNULL(_MC_v2_44,
                                                              0)
                                    * ISNULL(_MC_v2_440, 0) + ISNULL(_MC_v2_SD,
                                                              0)
                                    * ISNULL(_MC_v2_SD0, 0) + ISNULL(_MC_v2_FV,
                                                              0)
                                    * ISNULL(_MC_v2_FV0, 0) + ISNULL(_MC_v2_48,
                                                              0)
                                    * ISNULL(_MC_v2_480, 0) + ISNULL(_MC_v2_CA,
                                                              0)
                                    * ISNULL(_MC_v2_CA0, 0) + ISNULL(_MC_v2_66,
                                                              0)
                                    * ISNULL(_MC_v2_660, 0) + ISNULL(_MC_v2_51,
                                                              0)
                                    * ISNULL(_MC_v2_510, 0) + ISNULL(_MC_v2_SR,
                                                              0)
                                    * ISNULL(_MC_v2_SR0, 0) + ISNULL(_MC_v2_71,
                                                              0)
                                    * ISNULL(_MC_v2_710, 0) + ISNULL(_MC_v2_NB,
                                                              0)
                                    * ISNULL(_MC_v2_NB0, 0) + ISNULL(_MC_v2_9K,
                                                              0)
                                    * ISNULL(_MC_v2_9K0, 0) + ISNULL(_MC_v2_WL,
                                                              0)
                                    * ISNULL(_MC_v2_WL0, 0) + ISNULL(_MC_v2_64,
                                                              0)
                                    * ISNULL(_MC_v2_640, 0) + ISNULL(_MC_v2_VA,
                                                              0)
                                    * ISNULL(_MC_v2_VA0, 0) + ISNULL(_MC_v2_80,
                                                              0)
                                    * ISNULL(_MC_v2_800, 0) + ISNULL(_MC_v2_03,
                                                              0)
                                    * ISNULL(_MC_v2_030, 0) + ISNULL(_MC_v2_06,
                                                              0)
                                    * ISNULL(_MC_v2_060, 0) + ISNULL(_MC_v2_CO,
                                                              0)
                                    * ISNULL(_MC_v2_CO0, 0) + ISNULL(_MC_v2_10,
                                                              0)
                                    * ISNULL(_MC_v2_100, 0) + ISNULL(_MC_v2_09,
                                                              0)
                                    * ISNULL(_MC_v2_090, 0) + ISNULL(_MC_v2_11,
                                                              0)
                                    * ISNULL(_MC_v2_110, 0) + ISNULL(_MC_v2_NF,
                                                              0)
                                    * ISNULL(_MC_v2_NF0, 0) + ISNULL(_MC_v2_PO,
                                                              0)
                                    * ISNULL(_MC_v2_PO0, 0) + ISNULL(_MC_v2_CZ,
                                                              0)
                                    * ISNULL(_MC_v2_CZ0, 0) + ISNULL(_MC_v2_82,
                                                              0)
                                    * ISNULL(_MC_v2_820, 0) + ISNULL(_MC_v2_34,
                                                              0)
                                    * ISNULL(_MC_v2_340, 0) + ISNULL(_MC_v2_72,
                                                              0)
                                    * ISNULL(_MC_v2_720, 0) + ISNULL(_MC_v2_IT,
                                                              0)
                                    * ISNULL(_MC_v2_IT0, 0) + ISNULL(_MC_v2_15,
                                                              0)
                                    * ISNULL(_MC_v2_150, 0) + ISNULL(_MC_v2_50,
                                                              0)
                                    * ISNULL(_MC_v2_500, 0) + ISNULL(_MC_v2_26,
                                                              0)
                                    * ISNULL(_MC_v2_260, 0) + ISNULL(_MC_v2_30,
                                                              0)
                                    * ISNULL(_MC_v2_300, 0) + ISNULL(_MC_v2_90,
                                                              0)
                                    * ISNULL(_MC_v2_900, 0) + ISNULL(_MC_v2_CL,
                                                              0)
                                    * ISNULL(_MC_v2_CL0, 0) + ISNULL(_MC_v2_MS,
                                                              0)
                                    * ISNULL(_MC_v2_MS0, 0) + ISNULL(_MC_v2_12,
                                                              0)
                                    * ISNULL(_MC_v2_120, 0) + ISNULL(_MC_v2_25,
                                                              0)
                                    * ISNULL(_MC_v2_250, 0) + ISNULL(_MC_v2_07,
                                                              0)
                                    * ISNULL(_MC_v2_070, 0) + ISNULL(_MC_v2_FQ,
                                                              0)
                                    * ISNULL(_MC_v2_FQ0, 0) + ISNULL(_MC_v2_27,
                                                              0)
                                    * ISNULL(_MC_v2_270, 0) + ISNULL(_MC_v2_76,
                                                              0)
                                    * ISNULL(_MC_v2_760, 0)
                                    + ISNULL(_MC_v2_NONE, 0)
                                    * ISNULL(_MC_v2_NONE0, 0)
                                    + ISNULL(_m_age_1 * _m_age, 0)
                                    + ISNULL(_m_monthlyincome_1
                                             * _m_monthlyincome, 0)
                                    + ISNULL(_m_ltc_1 * _m_ltc, 0)) ,
                            ApprovalID ,
                            storetype ,
                            leaseaddeddate = CONVERT(DATE, LeaseAddedDate) ,
                            StoreID
                  FROM      #core_pre_scoring
                ) b



  --select * from #core_pre_scoring     where   approvalid='22QG42M'

/* begin code for scoring noncore*/
        IF OBJECT_ID('tempdb..#noncore_pre_scoring') IS NOT NULL
        DROP TABLE #noncore_pre_scoring
        SELECT  a.* ,
                b.*
        INTO    #noncore_pre_scoring
        FROM    #bin_fraud_master a
                CROSS JOIN ( SELECT *
                             FROM   analytics..orig_parameter_coef_v2
                             WHERE  model = 'NONCORE_MODEL'
                           ) b
        WHERE   a.storetype <> 'CORE'





/* samll issues resulting in 42 nulls out of 600,000*/
/*ltc issue */ /* no biweekly for core training data*/
/*-------------------------Begin Code for Scoring noncore  */

                    /*intercept*/

        IF OBJECT_ID('tempdb..#noncore_score') IS NOT NULL
        DROP TABLE #noncore_score
        SELECT  b.* ,
                probability = b.z / ( 1 + b.z )
        INTO    #noncore_score
        FROM    ( SELECT    z = EXP(intercept
                                    + ( CASE WHEN _mc_add_flag = 0
                                             THEN _mc_add_flag0
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_paymentfrequency = '14 Day'
                                             THEN _mc_paymentfrequency14_day
                                             WHEN _mc_paymentfrequency = '28 Day'
                                             THEN _mc_paymentfrequency28_day
                                             WHEN _mc_paymentfrequency = 'bi-weekly'
                                             THEN _mc_paymentfrequencybi_weekly
                                             WHEN _mc_paymentfrequency = 'Monthly'
                                             THEN 0
                                        END )
                                    + ( CASE WHEN _mc_primarypaymentmethod = 'ACH'
                                             THEN _mc_primarypaymentmethodACH
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_seasonality = 1
                                             THEN _mc_seasonality1
                                             WHEN _mc_seasonality = 2
                                             THEN _mc_seasonality2
                                             WHEN _mc_seasonality = 3
                                             THEN _mc_seasonality3
                                             WHEN _mc_seasonality = 4
                                             THEN _mc_seasonality4
                                             WHEN _mc_seasonality = 5
                                             THEN _mc_seasonality5
                                             WHEN _mc_seasonality = 6
                                             THEN _mc_seasonality6
                                             WHEN _mc_seasonality = 7
                                             THEN _mc_seasonality7
                                             WHEN _mc_seasonality = 8
                                             THEN _mc_seasonality8
                                             WHEN _mc_seasonality = 9
                                             THEN _mc_seasonality9
                                             WHEN _mc_seasonality = 10
                                             THEN _mc_seasonality10
                                             WHEN _mc_seasonality = 11
                                             THEN _mc_seasonality11
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_state_flag = 0
                                             THEN _MC_state_flag0
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_zipgroup1 = '0'
                                             THEN _mc_zipgroup10
                                             WHEN _mc_zipgroup1 = '1'
                                             THEN _mc_zipgroup11
                                             WHEN _mc_zipgroup1 = '2'
                                             THEN _mc_zipgroup12
                                             WHEN _mc_zipgroup1 = '3'
                                             THEN _mc_zipgroup13
                                             WHEN _mc_zipgroup1 = '4'
                                             THEN _mc_zipgroup14
                                             WHEN _mc_zipgroup1 = '5'
                                             THEN _mc_zipgroup15
                                             WHEN _mc_zipgroup1 = '6'
                                             THEN _mc_zipgroup16
                                             WHEN _mc_zipgroup1 = '7'
                                             THEN _mc_zipgroup17
                                             WHEN _mc_zipgroup1 = '8'
                                             THEN _mc_zipgroup18
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_card_appear_number = 0
                                             THEN _mc_card_appear_number0
                                             WHEN _mc_card_appear_number = 1
                                             THEN _mc_card_appear_number1
                                             WHEN _mc_card_appear_number = 2
                                             THEN _mc_card_appear_number2
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_storetype = 'KMT'
                                             THEN _mc_storetypeKMT
                                             WHEN _mc_storetype = 'FLSAUTO'
                                             THEN _mc_storetypeFLSAUTO
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_sku_dif = 0
                                             THEN _mc_sku_dif0
                                             WHEN _mc_sku_dif = 1
                                             THEN _mc_sku_dif1
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_languagepreference = 0
                                             THEN _mc_languagepreference0
                                             WHEN _mc_languagepreference = 1
                                             THEN _mc_languagepreference1
                                             WHEN _mc_languagepreference = 2
                                             THEN _mc_languagepreference2
                                             WHEN _mc_languagepreference = 3
                                             THEN _mc_languagepreference3
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_idtype = 'Drivers License'
                                             THEN _mc_idtypeDrivers_License
                                             WHEN _mc_idtype = 'Green Card'
                                             THEN _mc_idtypeGreen_Card
                                             WHEN _mc_idtype = 'Military ID'
                                             THEN _mc_idtypeMilitary_ID
                                             WHEN _mc_idtype = 'MMCC'
                                             THEN _mc_idtypeMMCC
                                             WHEN _mc_idtype = 'Missing'
                                             THEN _mc_idtypeMissing
                                             WHEN _mc_idtype = 'Passport'
                                             THEN _mc_idtypePassport
                                             WHEN _mc_idtype = 'State ID'
                                             THEN _mc_idtypeState_ID
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mcfp_quintile = 1
                                             THEN _mcfp_quintile1
                                             WHEN _mcfp_quintile = 2
                                             THEN _mcfp_quintile2
                                             WHEN _mcfp_quintile = 3
                                             THEN _mcfp_quintile3
                                             WHEN _mcfp_quintile = 4
                                             THEN _mcfp_quintile4
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_cc_orig = 0
                                             THEN _mc_cc_orig0
                                             WHEN _mc_cc_orig = 1
                                             THEN _mc_cc_orig1
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_nas = '00' THEN _mc_nas0
                                             WHEN _mc_nas = '01' THEN _mc_nas1
                                             WHEN _mc_nas = '02' THEN _mc_nas2
                                             WHEN _mc_nas = '03' THEN _mc_nas3
                                             WHEN _mc_nas = '04' THEN _mc_nas4
                                             WHEN _mc_nas = '05' THEN _mc_nas5
                                             WHEN _mc_nas = '06' THEN _mc_nas6
                                             WHEN _mc_nas = '07' THEN _mc_nas7
                                             WHEN _mc_nas = '08' THEN _mc_nas8
                                             WHEN _mc_nas = '09' THEN _mc_nas9
                                             WHEN _mc_nas = '10'
                                             THEN _mc_nas10
                                             WHEN _mc_nas = '11'
                                             THEN _mc_nas11
                                             WHEN _mc_nas = '12'
                                             THEN _mc_nas12
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_cvi = '0' THEN _mc_cvi0
                                             WHEN _mc_cvi = '10'
                                             THEN _mc_cvi10
                                             WHEN _mc_cvi = '20'
                                             THEN _mc_cvi20
                                             WHEN _mc_cvi = '30'
                                             THEN _mc_cvi30
                                             WHEN _mc_cvi = '40'
                                             THEN _mc_cvi40
                                             WHEN _mc_cvi = '50'
                                             THEN _mc_cvi50
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_sdistance = 1
                                             THEN _mc_sdistance1
                                             WHEN _mc_sdistance = 2
                                             THEN _mc_sdistance2
                                             WHEN _mc_sdistance = 3
                                             THEN _mc_sdistance3
                                             WHEN _mc_sdistance = 4
                                             THEN _mc_sdistance4
                                             WHEN _mc_sdistance = 5
                                             THEN _mc_sdistance5
                                             WHEN _mc_sdistance = 6
                                             THEN _mc_sdistance6
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_sage_orig = 1
                                             THEN _mc_sage_orig1
                                             WHEN _mc_sage_orig = 2
                                             THEN _mc_sage_orig2
                                             WHEN _mc_sage_orig = 3
                                             THEN _mc_sage_orig3
                                             WHEN _mc_sage_orig = 4
                                             THEN _mc_sage_orig4
                                             ELSE 0
                                        END )
                                    + ( CASE WHEN _mc_v2_z_sum = 1
                                             THEN _MC_z_sum1
                                             WHEN _mc_v2_z_sum = 2
                                             THEN _MC_z_sum2
                                             WHEN _mc_v2_z_sum = 3
                                             THEN _MC_z_sum3
                                             WHEN _mc_v2_z_sum = 4
                                             THEN _MC_z_sum4
                                             WHEN _mc_v2_z_sum = 5
                                             THEN _MC_z_sum5
                                             WHEN _mc_v2_z_sum = 6
                                             THEN _MC_z_sum6
                                             WHEN _mc_v2_z_sum = 7
                                             THEN _MC_z_sum7
                                             WHEN _mc_v2_z_sum = 8
                                             THEN _MC_z_sum8
                                             WHEN _mc_v2_z_sum = 9
                                             THEN _MC_z_sum9
                                             WHEN _mc_v2_z_sum = 10
                                             THEN _MC_z_sum10
                                             WHEN _mc_v2_z_sum = 11
                                             THEN _MC_z_sum11
                                             WHEN _mc_v2_z_sum = 12
                                             THEN _MC_z_sum12
                                             WHEN _mc_v2_z_sum = 13
                                             THEN _MC_z_sum13
                                             WHEN _mc_v2_z_sum = 14
                                             THEN _MC_z_sum14
                                             WHEN _mc_v2_z_sum = 15
                                             THEN _MC_z_sum15
                                             WHEN _mc_v2_z_sum = 16
                                             THEN _MC_z_sum16
                                             WHEN _mc_v2_z_sum = 17
                                             THEN _MC_z_sum17
                                             ELSE 0
                                        END ) + ISNULL(_MC_v2_30, 0)
                                    * ISNULL(_MC_v2_300, 0) + ISNULL(_MC_v2_90,
                                                              0)
                                    * ISNULL(_MC_v2_900, 0) + ISNULL(_MC_v2_CL,
                                                              0)
                                    * ISNULL(_MC_v2_CL0, 0) + ISNULL(_MC_v2_MS,
                                                              0)
                                    * ISNULL(_MC_v2_MS0, 0) + ISNULL(_MC_v2_12,
                                                              0)
                                    * ISNULL(_MC_v2_120, 0) + ISNULL(_MC_v2_25,
                                                              0)
                                    * ISNULL(_MC_v2_250, 0) + ISNULL(_MC_v2_07,
                                                              0)
                                    * ISNULL(_MC_v2_070, 0) + ISNULL(_MC_v2_FQ,
                                                              0)
                                    * ISNULL(_MC_v2_FQ0, 0) + ISNULL(_MC_v2_27,
                                                              0)
                                    * ISNULL(_MC_v2_270, 0) + ISNULL(_MC_v2_76,
                                                              0)
                                    * ISNULL(_MC_v2_760, 0) + ISNULL(_MC_v2_BO,
                                                              0)
                                    * ISNULL(_MC_v2_BO0, 0) + ISNULL(_MC_v2_85,
                                                              0)
                                    * ISNULL(_MC_v2_850, 0) + ISNULL(_MC_v2_9D,
                                                              0)
                                    * ISNULL(_MC_v2_9D0, 0) + ISNULL(_MC_v2_44,
                                                              0)
                                    * ISNULL(_MC_v2_440, 0) + ISNULL(_MC_v2_SD,
                                                              0)
                                    * ISNULL(_MC_v2_SD0, 0) + ISNULL(_MC_v2_FV,
                                                              0)
                                    * ISNULL(_MC_v2_FV0, 0) + ISNULL(_MC_v2_82,
                                                              0)
                                    * ISNULL(_MC_v2_820, 0) + ISNULL(_MC_v2_34,
                                                              0)
                                    * ISNULL(_MC_v2_340, 0) + ISNULL(_MC_v2_72,
                                                              0)
                                    * ISNULL(_MC_v2_720, 0) + ISNULL(_MC_v2_IT,
                                                              0)
                                    * ISNULL(_MC_v2_IT0, 0) + ISNULL(_MC_v2_15,
                                                              0)
                                    * ISNULL(_MC_v2_150, 0) + ISNULL(_MC_v2_50,
                                                              0)
                                    * ISNULL(_MC_v2_500, 0) + ISNULL(_MC_v2_26,
                                                              0)
                                    * ISNULL(_MC_v2_260, 0) + ISNULL(_MC_v2_VA,
                                                              0)
                                    * ISNULL(_MC_v2_VA0, 0) + ISNULL(_MC_v2_80,
                                                              0)
                                    * ISNULL(_MC_v2_800, 0) + ISNULL(_MC_v2_03,
                                                              0)
                                    * ISNULL(_MC_v2_030, 0) + ISNULL(_MC_v2_06,
                                                              0)
                                    * ISNULL(_MC_v2_060, 0) + ISNULL(_MC_v2_CO,
                                                              0)
                                    * ISNULL(_MC_v2_CO0, 0) + ISNULL(_MC_v2_10,
                                                              0)
                                    * ISNULL(_MC_v2_100, 0) + ISNULL(_MC_v2_09,
                                                              0)
                                    * ISNULL(_MC_v2_090, 0) + ISNULL(_MC_v2_11,
                                                              0)
                                    * ISNULL(_MC_v2_110, 0) + ISNULL(_MC_v2_NF,
                                                              0)
                                    * ISNULL(_MC_v2_NF0, 0) + ISNULL(_MC_v2_PO,
                                                              0)
                                    * ISNULL(_MC_v2_PO0, 0) + ISNULL(_MC_v2_CZ,
                                                              0)
                                    * ISNULL(_MC_v2_CZ0, 0) + ISNULL(_MC_v2_MN,
                                                              0)
                                    * ISNULL(_MC_v2_MN0, 0) + ISNULL(_MC_v2_02,
                                                              0)
                                    * ISNULL(_MC_v2_020, 0) + ISNULL(_MC_v2_75,
                                                              0)
                                    * ISNULL(_MC_v2_750, 0) + ISNULL(_MC_v2_MI,
                                                              0)
                                    * ISNULL(_MC_v2_MI0, 0) + ISNULL(_MC_v2_73,
                                                              0)
                                    * ISNULL(_MC_v2_730, 0) + ISNULL(_MC_v2_29,
                                                              0)
                                    * ISNULL(_MC_v2_290, 0) + ISNULL(_MC_v2_IS,
                                                              0)
                                    * ISNULL(_MC_v2_IS0, 0) + ISNULL(_MC_v2_19,
                                                              0)
                                    * ISNULL(_MC_v2_190, 0) + ISNULL(_MC_v2_48,
                                                              0)
                                    * ISNULL(_MC_v2_480, 0) + ISNULL(_MC_v2_CA,
                                                              0)
                                    * ISNULL(_MC_v2_CA0, 0) + ISNULL(_MC_v2_66,
                                                              0)
                                    * ISNULL(_MC_v2_660, 0) + ISNULL(_MC_v2_51,
                                                              0)
                                    * ISNULL(_MC_v2_510, 0) + ISNULL(_MC_v2_SR,
                                                              0)
                                    * ISNULL(_MC_v2_SR0, 0) + ISNULL(_MC_v2_71,
                                                              0)
                                    * ISNULL(_MC_v2_710, 0) + ISNULL(_MC_v2_NB,
                                                              0)
                                    * ISNULL(_MC_v2_NB0, 0) + ISNULL(_MC_v2_9K,
                                                              0)
                                    * ISNULL(_MC_v2_9K0, 0) + ISNULL(_MC_v2_WL,
                                                              0)
                                    * ISNULL(_MC_v2_WL0, 0) + ISNULL(_MC_v2_64,
                                                              0)
                                    * ISNULL(_MC_v2_640, 0) + ISNULL(_MC_v2_37,
                                                              0)
                                    * ISNULL(_MC_v2_370, 0) + ISNULL(_MC_v2_49,
                                                              0)
                                    * ISNULL(_MC_v2_490, 0) + ISNULL(_MC_v2_14,
                                                              0)
                                    * ISNULL(_MC_v2_140, 0) + ISNULL(_MC_v2_DI,
                                                              0)
                                    * ISNULL(_MC_v2_DI0, 0) + ISNULL(_MC_v2_RS,
                                                              0)
                                    * ISNULL(_MC_v2_RS0, 0) + ISNULL(_MC_v2_MO,
                                                              0)
                                    * ISNULL(_MC_v2_MO0, 0) + ISNULL(_MC_v2_PA,
                                                              0)
                                    * ISNULL(_MC_v2_PA0, 0) + ISNULL(_MC_v2_ZI,
                                                              0)
                                    * ISNULL(_MC_v2_ZI0, 0) + ISNULL(_MC_v2_74,
                                                              0)
                                    * ISNULL(_MC_v2_740, 0) + ISNULL(_MC_v2_28,
                                                              0)
                                    * ISNULL(_MC_v2_280, 0) + ISNULL(_MC_v2_08,
                                                              0)
                                    * ISNULL(_MC_v2_080, 0) + ISNULL(_MC_v2_52,
                                                              0)
                                    * ISNULL(_MC_v2_520, 0) + ISNULL(_MC_v2_89,
                                                              0)
                                    * ISNULL(_MC_v2_890, 0) + ISNULL(_MC_v2_16,
                                                              0)
                                    * ISNULL(_MC_v2_160, 0) + ISNULL(_MC_v2_04,
                                                              0)
                                    * ISNULL(_MC_v2_040, 0) + ISNULL(_MC_v2_40,
                                                              0)
                                    * ISNULL(_MC_v2_400, 0) + ISNULL(_MC_v2_31,
                                                              0)
                                    * ISNULL(_MC_v2_310, 0) + ISNULL(_MC_v2_38,
                                                              0)
                                    * ISNULL(_MC_v2_380, 0)
                                    + ISNULL(_MC_v2_NONE, 0)
                                    * ISNULL(_MC_v2_NONE0, 0)
                                    + ( CASE WHEN _MC_v2_NONE = 0
                                             THEN _MC_v2_NONE0
                                             WHEN _MC_v2_NONE IS NULL
                                             THEN _MC_v2_NONE0
                                             ELSE 0
                                        END ) + ISNULL(_m_age_1 * _m_age, 0)
                                    + --isnull(_m_monthlyincome_1 * _m_monthlyincome,0)+
          ISNULL(_m_ltc_1 * _m_ltc, 0)) ,
                            ApprovalID ,
                            storetype ,
                            leaseaddeddate = CONVERT(DATE, LeaseAddedDate) ,
                            StoreID
                  FROM      #noncore_pre_scoring
                ) b


 /* create store rank*/


        IF OBJECT_ID('tempdb..#quntile_prep') IS NOT NULL
        DROP TABLE #quntile_prep
        SELECT  ApprovalID ,
                storetype ,
                leaseaddeddate ,
                probability ,
                StoreID
        INTO    #quntile_prep
        FROM    #core_score
        UNION
        SELECT  ApprovalID ,
                storetype ,
                leaseaddeddate ,
                probability ,
                StoreID
        FROM    #noncore_score


        IF OBJECT_ID('tempdb..#fraud_quintile') IS NOT NULL
        DROP TABLE #fraud_quintile
        SELECT  storetype ,
                StoreID ,
                AVG(probability) store_probability
        INTO    #fraud_quintile
        FROM    #quntile_prep
        WHERE   leaseaddeddate > '2015-01-01'
        GROUP BY storetype ,
                StoreID

        IF OBJECT_ID('tempdb..#store_rank') IS NOT NULL
        DROP TABLE #store_rank
        SELECT  Store_rank = CASE WHEN NTILE(5) OVER ( PARTITION BY storetype ORDER BY store_probability ) = 1
                                  THEN 'A'
                                  WHEN NTILE(5) OVER ( PARTITION BY storetype ORDER BY store_probability ) = 2
                                  THEN 'B'
                                  WHEN NTILE(5) OVER ( PARTITION BY storetype ORDER BY store_probability ) = 3
                                  THEN 'C'
                                  WHEN NTILE(5) OVER ( PARTITION BY storetype ORDER BY store_probability ) = 4
                                  THEN 'D'
                                  WHEN NTILE(5) OVER ( PARTITION BY storetype ORDER BY store_probability ) = 5
                                  THEN 'F'
                             END ,
                *
        INTO    #store_rank
        FROM    #fraud_quintile
 /* create person rank */
        IF OBJECT_ID('tempdb..#person_rank') IS NOT NULL
        DROP TABLE #person_rank
        SELECT  a.* ,
                person_rank = CASE WHEN NTILE(5) OVER ( PARTITION BY a.storetype ORDER BY probability ) = 1
                                   THEN 'A'
                                   WHEN NTILE(5) OVER ( PARTITION BY a.storetype ORDER BY probability ) = 2
                                   THEN 'B'
                                   WHEN NTILE(5) OVER ( PARTITION BY a.storetype ORDER BY probability ) = 3
                                   THEN 'C'
                                   WHEN NTILE(5) OVER ( PARTITION BY a.storetype ORDER BY probability ) = 4
                                   THEN 'D'
                                   WHEN NTILE(5) OVER ( PARTITION BY a.storetype ORDER BY probability ) = 5
                                   THEN 'F'
                              END ,
                b.Store_rank ,
                b.store_probability
        INTO    #person_rank
        FROM    #quntile_prep a
                LEFT JOIN #store_rank b ON a.StoreID = b.StoreID
                                           AND a.storetype = b.storetype
        WHERE   leaseaddeddate > '2015-01-01'

/* create master Table */

        IF OBJECT_ID('analytics..GH_final_fraud_score') IS NOT NULL
        DROP TABLE   analytics..GH_final_fraud_score
        SELECT  a.* ,
                b.person_rank ,
                b.Store_rank ,
                b.store_probability
        INTO    analytics..GH_final_fraud_score
        FROM    #quntile_prep a
                LEFT JOIN #person_rank b ON a.ApprovalID = b.ApprovalID

-- Clean up Temp tables

        DROP TABLE #Bin_Fraud_master
        DROP TABLE #Fraud_master
        DROP TABLE #Store_attributes
        DROP TABLE #ach_credit_indicator
        DROP TABLE #card_appearance
        DROP TABLE #cart_attributes
        DROP TABLE #client_attributes
        DROP TABLE #core_pre_scoring
        DROP TABLE #core_score
        DROP TABLE #customer_zip
        DROP TABLE #customer_zip0
        DROP TABLE #dtest
        DROP TABLE #dtest0
        DROP TABLE #fp_attributes
        DROP TABLE #fraud_master2
        DROP TABLE #fraud_quintile
        DROP TABLE #lat_long
        DROP TABLE #lease_list
        DROP TABLE #lease_view_attributes
        DROP TABLE #ln_rsk
        DROP TABLE #max_approval
        DROP TABLE #noncore_pre_scoring
        DROP TABLE #noncore_score
        DROP TABLE #person_rank
        DROP TABLE #quntile_prep
        DROP TABLE #riskindicators
		DROP TABLE ##risk_indicators
        DROP TABLE #store_inception_date
        DROP TABLE #store_rank
        DROP TABLE #wnli_bank_attributes


