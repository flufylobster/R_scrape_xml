    ;with XMLNAMESPACES ('http://www.transunion.com/namespace' AS ns)
  select * from 

(select 
       pref.value('(text())[1]', 'varchar(32)') as code, id
from 
       analytics..xml1 cross APPLY

       testxml.nodes('(/ns:creditBureau//ns:code)') AS testxml(pref)
)  as Result


select * from 