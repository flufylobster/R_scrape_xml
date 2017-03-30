-----------------------------------------------------------------------------------------------------------------------------------------
/* Blitz Information table creation */
-- Data has is at the lease by day level, eg each row contains information for that lease on that day and is at an approvalID by day level of granularity\
-- Because of the the interval selected payemnts made that day will not be reflected in the reduction of a given lease's debt balance
-------------------------------------------------------------------------------------------------------------------------------------

----------------------------------------------
/* CHANGE LOG */
/* created by: George Hoersting  3/27/2017*/



----------------------------------------------


declare @STARTdate  date
	set @STARTdate='2016-10-01'
declare @ENDdate  date
	set @ENDdate=getdate()	
IF OBJECT_ID('tempdb..#DQ_BALANCE_BY_DAY') IS NOT NULL
    DROP TABLE #DQ_BALANCE_BY_DAY
select  c.caldate,
 c.weekdaylong,
 b.dpddate ,
 datediff( day, b.dpddate, c.caldate) as dq_days, 
 b.caldate dq_date,
 lv.leaseaddeddate,
 MOB = DATEDIFF(month, lv.leaseaddeddate,getdate()),   
 b.approvalbkey,
 b.approvalid,
 b.currentleasestatus,
 storetype=case when b.storetype =' ' then 'CORE' else b.storetype end ,
  dq_bal =  case when  b.balance < 0 then 0 else   b.balance end 
into #DQ_BALANCE_BY_DAY
from datawarehouse..dim_calendar c
left join
	(select c.caldate,store.storetype, d.approvalbkey, app.approvalid, dpddate, sum(d.balance) BALANCE, max(currentleasestatus) currentleasestatus
		from datawarehouse..dim_calendar c
		left join datawarehouse..DQjournal d
			on d.currentdate<c.caldate and d.nextdate>=c.caldate
		left join datawarehouse..dim_approval app
			on app.approvalbkey=d.approvalbkey
		left join datawarehouse..fact_leasesum fl
			on fl.approvalbkey=d.approvalbkey
		left join datawarehouse..dim_store store
			on store.storebkey=fl.storebkey			
		where (c.caldate between @STARTdate and  @ENDDATE) 	and currentleasestatus in ('90_DAYS_PAST_DUE','ACTIVE','COLLECTIONS','DEFAULT','INVALID_BANKING','NEW','SKIP','RECOVERY') and dpddate is not null				
			group by c.caldate,dpddate, store.storetype, d.approvalbkey ,app.approvalid) b
			on b.caldate=c.caldate 	 
		left join rto..wnli_leaseview lv
			on lv.approvalid=b.approvalid
			where c.caldate between @STARTdate and  @ENDDATE


/* create blitz table */

IF OBJECT_ID('tempdb..#DQ_BALANCE_BY_DAY_join') IS NOT NULL
    DROP TABLE #DQ_BALANCE_BY_DAY_join

---- join data create logic to caculate blitz cost
select 
 cb2.approvalid,
 app.approvalbkey,
 storetype,
 convert(date,ts) as blitz_date
 ,(case when paymentsuccessful=1 then cb2.totalpayment else 0 end) as total_collected
 ,(case when cardprocessingdescription='Authorize' then .20
     when cardprocessingdescription='Percent100' and paymentsuccessful=0 then .20*2
	 when cardprocessingdescription='Percent100' and paymentsuccessful=1 then .20 + .55
	 when cardprocessingdescription='Percent50'  and paymentsuccessful=0 then .20*3
	  when cardprocessingdescription='Percent50'  and paymentsuccessful=1 then .20*2 +.55
	 when cardprocessingdescription='Dollars25' and paymentsuccessful=0   then .20*4
	 when cardprocessingdescription='Dollars25' and paymentsuccessful=1   then .20*3 +.55
	 else 0 end) as blitz_cost
,(case when cardprocessingdescription='Authorize' then 1
     when cardprocessingdescription='Percent100'  then 2
	 when cardprocessingdescription='Percent50'   then 3
	 when cardprocessingdescription='Dollars25'   then 4
	 else 0 end) as tran_count
into #DQ_BALANCE_BY_DAY_join
from rto..wnli_cardblitzprocess2 cb2
	left join datawarehouse..dim_approval app 
		on app.approvalid=cb2.approvalid
    left join datawarehouse..fact_leasesum fl
		 on fl.approvalbkey=app.approvalbkey
	left join datawarehouse..dim_store store
		 on store.storebkey=fl.storebkey
where convert(date,ts) BETWEEN @STARTdate AND @ENDDATE

/* make this left join set*/
IF OBJECT_ID('tempdb..#DQ_BALANCE_BY_DAY_join2') IS NOT NULL
    DROP TABLE #DQ_BALANCE_BY_DAY_join2
select storetype, approvalbkey,
	blitz_date,
 sum(tran_count) as tran_count, 
 count(*) card_count, 
 sum(total_collected) total_collected,
 sum(blitz_cost) blitz_cost,
 sum(case when total_collected > 0 then 1 else 0 end)as success_count 
into #DQ_BALANCE_BY_DAY_join2
from #DQ_BALANCE_BY_DAY_join
group by storetype, approvalbkey,blitz_date

-- full outer join Cost and DQ

IF OBJECT_ID('tempdb..#Master_blitz') IS NOT NULL
    DROP TABLE #Master_blitz
 select dq.caldate, 
        dq.currentleasestatus, 
        dq.weekdaylong,
		 dq.dpddate,
		 dq_days,
		 dq.leaseaddeddate,
		 dq.MOB,
  coalesce(bc.approvalbkey, dq.approvalbkey) approvalbkey,
 dq.approvalid,
  storetype=case when coalesce(bc.storetype,dq.storetype)=' ' then 'CORE' else coalesce(bc.storetype,dq.storetype) end, 
  dq_bal,    
   bc.blitz_date,
   bc.tran_count,
   bc.total_collected blitz_payment,
   bc.blitz_cost,
   bc.success_count,
   bc.card_count
   into #Master_blitz
   from #DQ_BALANCE_BY_DAY dq 
	full outer join  #DQ_BALANCE_BY_DAY_join2 bc 
				on bc.approvalbkey=dq.approvalbkey and  bc.blitz_date=dq.CalDate 	
 /* cleanup*/
 drop table #DQ_BALANCE_BY_DAY
 drop table #DQ_BALANCE_BY_DAY_join2
 drop table #DQ_BALANCE_BY_DAY_join	




/* add blitz attempts since last succesful payment */
drop table #Master_blitz2
select  coalesce(caldate,blitz_date) master_date,
		 a. * ,
		 
		 dayssincesuccess=DATEDIFF(day, b.blitz_succ_date,getdate()),
		 blitz_succ_date,
		 
		 
		 blitz_attempt      = SUM( case when DATEDIFF(day, b.blitz_succ_date,getdate()) is null and blitz_date is not null   then 1
							 when DATEDIFF(day, b.blitz_succ_date,getdate()) > =0 and blitz_date is not null then 1 
			                 else 0 end) OVER( PARTITION BY a.approvalbkey ORDER BY coalesce(caldate,blitz_date) ROWS UNBOUNDED PRECEDING),
		
		
		cumulative_cost     = SUM( case when DATEDIFF(day, b.blitz_succ_date,getdate()) is null and blitz_date is not null   then a.blitz_cost
							 when DATEDIFF(day, b.blitz_succ_date,getdate()) > =0 and blitz_date is not null then a.blitz_cost
			                 else 0 end) OVER( PARTITION BY a.approvalbkey ORDER BY coalesce(caldate,blitz_date) ROWS UNBOUNDED PRECEDING),
		
		cum_success         =sum(case when success_count>0 then 1 else 0 end) over(partition by a.approvalbkey order by coalesce(caldate,blitz_date) rows  unbounded preceding),

		--blitz_attempt_reset= SUM( case when DATEDIFF(day, b.blitz_succ_date,getdate()) is null and blitz_date is not null and coalesce(caldate,blitz_date) > blitz_succ_date then 1
		--					 when DATEDIFF(day, b.blitz_succ_date,getdate()) > =0 and blitz_date is not null and coalesce(caldate,blitz_date) > blitz_succ_date  then 1 
		--	                 else 0 end) OVER( PARTITION BY a.approvalbkey ORDER BY coalesce(caldate,blitz_date) ROWS UNBOUNDED PRECEDING),
	   
	 --   cumulative_cost_reset =  SUM( case when DATEDIFF(day, b.blitz_succ_date,getdate()) is null and blitz_date is not null and coalesce(caldate,blitz_date) > blitz_succ_date  then a.blitz_cost
		--					     when DATEDIFF(day, b.blitz_succ_date,getdate()) > =0 and blitz_date is not null and coalesce(caldate,blitz_date) > blitz_succ_date then a.blitz_cost
		--	                     else 0 end) OVER( PARTITION BY a.approvalbkey ORDER BY coalesce(caldate,blitz_date) ROWS UNBOUNDED PRECEDING),
		
		
		cumulative_payments=sum(a.blitz_payment) over(PARTITION BY a.approvalbkey ORDER BY coalesce(caldate,blitz_date) ROWS UNBOUNDED PRECEDING),		
		c.first_blitz_date,
		blitzvintage=cast(year(c.first_blitz_date) as varchar(4)) + right('0'+ cast(month(c.first_blitz_date) as varchar(2)) ,2) ,
		lease_yyyymm= cast(year(a.leaseaddeddate) as varchar(4)) + right('0'+ cast(month(a.leaseaddeddate) as varchar(2)) ,2) 

into #Master_blitz2
from #Master_blitz a 
	left join ( select approvalbkey, max(blitz_date) blitz_succ_date from #Master_blitz where success_count  > 0 group by approvalbkey) b
		on a.approvalbkey=b.approvalbkey
	left join (select  approvalbkey, min(blitz_date) first_blitz_date  from #Master_blitz group by approvalbkey) c
		on c.approvalbkey=a.approvalbkey
/*clean up*/
drop table #master_blitz



drop table  #mb5
select  *,
         cum_cost=sum(blitz_cost) over(partition by approvalbkey, cum_success order by master_date rows  unbounded preceding),
		 cum_attempt=sum(case when blitz_cost is not null then 1 else 0 end) over(partition by approvalbkey, cum_success order by master_date rows  unbounded preceding)
into #mb5
from #Master_blitz2

/* create permanent table */
drop table analytics..gh_blitz_by_day2 
 select a.*  
	into analytics..gh_blitz_by_day2
	from #mb5 a
 where master_date > ='2016-01-01'
/* clean up */
 drop table #master_blitz2
 drop table #mb5

