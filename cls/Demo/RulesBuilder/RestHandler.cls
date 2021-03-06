Include %IKPublic

IncludeGenerator %IKPublic

/// NOTE: this class was built to support versions prior to 2016.2 and therefore does
/// not yet take advantage of the JSON features or iKnow REST API added since.
Class Demo.RulesBuilder.RestHandler Extends %CSP.REST
{

Parameter IKPAGESIZE As INTEGER = 1000;

/// As the app only shows spread, this filter mode will do all we need with less work than
/// the classic $$$FILTERALLANDSORT
Parameter IKPFILTERMODE As INTEGER = {$$$FILTERSPREADANDSORT};

Parameter JSONFORMATPARAMS As STRING = "aelotwu";

Parameter CONTENTTYPE = "application/json";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>

<Route Url="/Domain/:domain/Sentences/Entity/:entity" Method="GET" Call="GetSentencesByEntity"/>
<Route Url="/Domain/:domain/Sentences/Entity" Method="POST" Call="GetSentencesByEntity"/>

<Route Url="/Domain/:domain/Entities" Method="POST" Call="GetEntities"/>

<Route Url="/Domain/:domain/Blacklists" Method="GET" Call="GetBlacklists"/>

<Route Url="/Domain/:domain/Dictionaries" Method="GET" Call="GetDictionaries"/>
<Route Url="/Domain/:domain/Dictionaries" Method="POST" Call="UpdateDictionaries"/>

<Route Url="/Domain/:domain/RuleDefinitions" Method="GET" Call="GetRuleDefs"/>
<Route Url="/Domain/:domain/RuleDefinitions" Method="POST" Call="UpdateRuleDef"/>

<Route Url="/Domain/:domain/ExtractionResults/:docName" Method="GET" Call="GetExtractionResults"/>

<Route Url="/Domain/:domain/Index" Method="POST" Call="Index"/>

<Route Url="/Domain/:domain/Extract/:parID/:srcId" Method="GET" Call="ExtractParagraph"/>

<Route Url="/Domain/:domain/Parse" Method="POST" Call="Parse"/>

<Route Url="/Domain/:domain/Sources" Method="GET" Call="GetSources" />
<Route Url="/Domain/:domain/Sources/:srcId" Method="GET" Call="GetSourceText" />

</Routes>
}

/// Retrieve all Demo.RulesBuilder.ExtractionResult entries for a given source, optionally
/// limited to those of a designated sentence.
ClassMethod GetExtractionResults(pDomainId As %Integer, pSourceId As %Integer, pSentId As %Integer = 0) As %Status
{
	set tSC = $$$OK
	try {
		set tJSON = ##class(%ZEN.proxyObject).%New()
		set tJSON.ExtractionResults = ##class(%ListOfObjects).%New()
		
		if (pSourceId > 0) {
			set tSourceObj = ##class(%iKnow.Objects.Source).PKINDEXOpen(pDomainId, pSourceId)
		} else {
			set tSourceObj = ##class(%iKnow.Objects.VirtualSource).PKINDEXOpen(pDomainId, $zabs(pSourceId))
		}
		
		set tStatement = ##class(%SQL.Statement).%New()
		set tSC = tStatement.%Prepare("SELECT ID FROM Demo_RulesBuilder.ExtractionResult WHERE DomainId = ? AND SourceId = ? AND Score > 0"_$s(pSentId:" AND SentenceId = "_pSentId, 1:"")_" ORDER BY Score DESC")
		quit:$$$ISERR(tSC)
		set tResult = tStatement.%Execute(pDomainId, pSourceId)
		while tResult.%Next() {
			set tExtract = ##class(Demo.RulesBuilder.ExtractionResult).%OpenId(tResult.%GetData(1))
			set tProxy = ##class(%ZEN.proxyObject).%New()
			set tProxy.HighlightingResult = tExtract.HighlightingResult
			set tProxy.MeetsMandatory = tExtract.MeetsMandatory
			set tProxy.MeetsOrder = tExtract.MeetsOrder
			set tProxy.Score = tExtract.Score
			set:tExtract.SentenceId tProxy.SentenceId = tExtract.SentenceId-tSourceObj.FirstSentenceId+1
			
			set tProxy.RuleDefinition = ##class(%ZEN.proxyObject).%New()
			set tProxy.RuleDefinition.DomainId = tExtract.RuleDefinition.DomainId
			set tProxy.RuleDefinition.Name = tExtract.RuleDefinition.Name
			set tProxy.RuleDefinition.MinimumScore = tExtract.RuleDefinition.MinimumScore
			set tProxy.RuleDefinition.EnforceSequence = tExtract.RuleDefinition.EnforceSequence
			set tProxy.RuleDefinition.StringRepresentation = tExtract.RuleDefinition.StringRepresentation
			set tProxy.RuleDefinition.Elements = ##class(%ListOfObjects).%New()
			for i = 1:1:tExtract.RuleDefinition.Elements.Count() {
				set tElem = ##class(%ZEN.proxyObject).%New()
				set tElem.Name = tExtract.RuleDefinition.Elements.GetAt(i).Name
				set tElem.Count = tExtract.RuleDefinition.Elements.GetAt(i).Count
				set tElem.Negation = tExtract.RuleDefinition.Elements.GetAt(i).Negation
				set tElem.Type = tExtract.RuleDefinition.Elements.GetAt(i).Type
				do tProxy.RuleDefinition.Elements.Insert(tElem)
			}
			
			set tProxy.MatchedElements = ##class(%ListOfObjects).%New()
			for i = 1:1:tExtract.MatchedElements.Count() {
				set tMatchedElem = tExtract.MatchedElements.GetAt(i)
				set tElem = ##class(%ZEN.proxyObject).%New()
				set tElem.RuleElement = tProxy.RuleDefinition.Elements.GetAt(tMatchedElem.RuleElementSeq)
				set tElem.MatchScore = tMatchedElem.MatchScore
				set tElem.Color = tMatchedElem.Color
				set tElem.DictionaryTermId = tMatchedElem.DictionaryTermId
				set tElem.Literal = tMatchedElem.Literal
				set tElem.FirstEntOccId = tMatchedElem.FirstEntOccId
				set tElem.Negation = tMatchedElem.Negation
				set tElem.IsSecondary = tMatchedElem.IsSecondary
				
				set tDictionaryTerm = ##class(%iKnow.Objects.DictionaryTerm).PKINDEXOpen(pDomainId, tMatchedElem.DictionaryTermId)
				set tElem.DictionaryTerm = ##class(%ZEN.proxyObject).%New()
				set tElem.DictionaryTerm.String = tDictionaryTerm.String
				
				// derive value
				set tEntOccId = "", tValue = ""
				while 1 {
					set tOutput = tMatchedElem.EntOccOutput.GetNext(.tEntOccId)
					quit:tEntOccId=""
					continue:tOutput=""
					set tValue = tValue_$lb(tOutput)
				}
				
				// if no output is found, use the item name
				set:tValue="" tValue = $lb(tDictionaryTerm.DictionaryItem.Name)
				set tElem.Value = $lts(tValue)
				
				do tProxy.MatchedElements.Insert(tElem)
			}
			do tJSON.ExtractionResults.Insert(tProxy)
		}
		
		do tJSON.%ToJSON(,..#JSONFORMATPARAMS)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit ..ErrorHandler(tSC)
}

/// Match supplied element (paragraph / sentence) against all Demo.RulesBuilder.RuleDefinition entries
/// If pPargraphID > 0, proceed extracting from Demo.RulesBuilder.Paragraph entry
/// If pPragraphID < 0, use as sentence ID and proceed with that sentence only 
ClassMethod ExtractParagraph(pDomainId As %Integer, pParagraphID As %Integer, pSourceId As %Integer) As %Status
{
	set tSC = $$$OK
	try {
		if pParagraphID < 0 {
			set tSentId = $zabs(pParagraphID), pParagraphID = 0
		} else {
			set tSentId = 0
		}
		
		&SQL(DELETE FROM Demo_RulesBuilder.ExtractionResult WHERE DomainId = :pDomainId AND SourceId = :pSourceId)
		set tStatement = ##class(%SQL.Statement).%New()
		set tSC = tStatement.%Prepare("SELECT ID FROM Demo_RulesBuilder.RuleDefinition WHERE DomainId = ?")
		quit:$$$ISERR(tSC)
		set tResult = tStatement.%Execute(pDomainId) 
		while tResult.%Next() {
			set tSC = ##class(RuleDefinition).%OpenId(tResult.%Get("ID")).CheckMatches(pSourceId, pParagraphID, tSentId)
			quit:$$$ISERR(tSC)
		}
		quit:$$$ISERR(tSC)
		
		set tSC = ..GetExtractionResults(pDomainId, pSourceId, tSentId)
		quit:$$$ISERR(tSC)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit ..ErrorHandler(tSC)
}

/// Input: either of
///   { txt : ... }   >> index text and proceed per sentence
///   { src : 123 }   >> use source and proceed per sentence
///   { obj : { ... } }  >> leverage supplied paragraph structure
ClassMethod Index(pDomainId As %Integer) As %Status
{
	set tSC = $$$OK
	try {
		set tJSONString = ""
		while '%request.Content.AtEnd {
			set tJSONString = tJSONString_$zcvt(%request.Content.ReadLine(),"I","UTF8")
		}
		set tSC = ##class(%ZEN.Auxiliary.jsonProvider).%ConvertJSONToObject(tJSONString,,.tJSON)
		quit:$$$ISERR(tSC)
		
		set tDomainName = $system.iKnow.GetDomainName(pDomainId)
		set tDocName = tJSON.doc.documentName
		
		// first clean up old records and persist paragraphs
		&SQL(DELETE FROM Demo_RulesBuilder.Paragraph WHERE DocumentName = :tDocName)
		&SQL(DELETE FROM Demo_RulesBuilder.ExtractionResult WHERE DomainId = :pDomainId AND DocumentName = :tDocName)
		
		
		set tResult = ##class(%ZEN.proxyObject).%New()
		set tResult.paragraphs = ##class(%ListOfObjects).%New()
		set tMarkup("MATCH")="<b>"
		set tMarkup("ATTRIBUTE",$$$IKATTNEGATION) = "<font style='color: DarkRed;'>"
		
		if (tJSON.txt '= "") {
			set tSC = $system.iKnow.IndexString(tDomainName, 123, tJSON.txt,,1, .tSrcId)
			quit:$$$ISERR(tSC)
			set tJSON.src = tSrcId
		}
		
		if (tJSON.src '= "") {
			
			// when starting from an existing source, treat sentences as paragraphs
			set vSrcID = $s(tJSON.src<0:$zabs(tJSON.src), 1:0)
			set tSC = ##class(%iKnow.Queries.SentenceAPI).GetBySource(.tSentences, pDomainId, tJSON.src, 0, 0)
			quit:$$$ISERR(tSC)
			
			set i = ""
			for {
				set i = $order(tSentences(i), 1, tSentData)
				quit:i=""
				
				set tSentId = $lg(tSentData,1)
				set tPar = ##class(%ZEN.proxyObject).%New()
				set tPar.documentName = tDocName
				set tPar.paragraphId = -tSentId
				set tPar.startPos = tSentId
				set tPar.key = tSentId
				set tPar.fullKey = tSentId
				set tPar.fullText = ##class(%iKnow.Queries.SentenceAPI).GetHighlighted(pDomainId, tSentId, .tMarkup, vSrcID)
				set tPar.sourceId = tJSON.src
				
				// add flag for *any* match
				if (vSrcID) {
					// not supported
				} else {
					set tSC = ##class(%iKnow.Matching.MatchingAPI).GetMatchesBySentence(.tMatches, pDomainId, tSentId,, 0)
					quit:$$$ISERR(tSC)
					set tPar.matchCount = +$o(tMatches(""),-1)
				}

				do tResult.paragraphs.Insert(tPar)
			}
			quit:$$$ISERR(tSC)
			
		} else {
			set tSC = ##class(Demo.RulesBuilder.Paragraph).SaveFromProxy(tJSON.doc)
			quit:$$$ISERR(tSC)

			// now update domain
			set tSC = ##class(Demo.RulesBuilder.Utils).LoadDocument(tDocName, pDomainId, .vSrcIDs)
			quit:$$$ISERR(tSC)

			set vSrcID = ""
			for {
				set vSrcID = $order(vSrcIDs(vSrcID),1,tParID)
				quit:vSrcID=""
				set tPar = ##class(Paragraph).%OpenId(tParID).ToProxy(pDomainId,.tMarkup,-1)
				set tPar.sourceId = vSrcID
				
				// add flag for *any* match
				set tSC = ##class(%iKnow.Matching.MatchingAPI).GetMatchesBySourceId(.tMatches, pDomainId, tPar.sourceId,, 0)
				quit:$$$ISERR(tSC)
				set tPar.matchCount = +$o(tMatches(""),-1)
				
				do tResult.paragraphs.Insert(tPar)
			}
			quit:$$$ISERR(tSC)
		}
		
		set:$data(%response) %response.ContentType="application/json"
		do tResult.%ToJSON(,..#JSONFORMATPARAMS)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit ..ErrorHandler(tSC)
}

ClassMethod Parse(pDomainId As %Integer) As %Status
{
	set tSC = $$$OK
	try {
		set tJSONString = ""
		while '%request.Content.AtEnd {
			set tJSONString = tJSONString_$zcvt(%request.Content.ReadLine(),"I","UTF8")
		}
		set tSC = ##class(%ZEN.Auxiliary.jsonProvider).%ConvertJSONToObject(tJSONString,,.tJSON)
		quit:$$$ISERR(tSC)
		
		// TODO: de-hardcode separator?
		set tSC = ##class(Demo.RulesBuilder.Paragraph).ParseString(.tObject, tJSON.Text,, $c(10))
		quit:$$$ISERR(tSC)
		
		set:$data(%response) %response.ContentType="application/json"
		do tObject.%ToJSON(,..#JSONFORMATPARAMS)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit ..ErrorHandler(tSC)
}

ClassMethod GetRuleDefs(pDomainId As %Integer) As %Status
{
	set tSC = $$$OK
	try {
		set tJSON = ##class(%ZEN.proxyObject).%New()
		set tJSON.RuleDefinitions = ##class(%ListOfObjects).%New()
		
		set tStatement = ##class(%SQL.Statement).%New()
		set tSC = tStatement.%Prepare("SELECT ID FROM Demo_RulesBuilder.RuleDefinition WHERE DomainId = ?")
		quit:$$$ISERR(tSC)
		set tResult = tStatement.%Execute(pDomainId)
		while tResult.%Next() {
			set tRuleDef = ##class(Demo.RulesBuilder.RuleDefinition).%OpenId(tResult.%GetData(1))
			set tProxy = ##class(%ZEN.proxyObject).%New()
			set tProxy.ID = tResult.%GetData(1)
			set tProxy.DomainId = tRuleDef.DomainId
			set tProxy.Name = tRuleDef.Name
			set tProxy.EnforceSequence = tRuleDef.EnforceSequence
			set tProxy.StringRepresentation = tRuleDef.StringRepresentation
			set tProxy.Elements = ##class(%ListOfObjects).%New()
			for i = 1:1:tRuleDef.Elements.Count() {
				set tElem = ##class(%ZEN.proxyObject).%New()
				set tElem.Name = tRuleDef.Elements.GetAt(i).Name
				set tElem.Count = tRuleDef.Elements.GetAt(i).Count
				set tElem.Negation = tRuleDef.Elements.GetAt(i).Negation
				set tElem.Type = tRuleDef.Elements.GetAt(i).Type
				if (tElem.Type="dictionary") {
					set tElem.DictName = tElem.Name
					set tElem.ItemURI = "ANY"
					if (##class(%iKnow.Matching.DictionaryAPI).GetDictionaryId(pDomainId, tElem.DictName)<=0) {
						set tSC = $$$ERROR($$$GeneralError, "WARNING: dictionary '"_tElem.DictName_"' is referred in rule '"_tRuleDef.Name_"' and no longer present!")
					}
				} else {
					set tElem.ItemURI = tElem.Name
					set tDictItemId = ##class(%iKnow.Matching.DictionaryAPI).GetDictionaryItemIdByURI(pDomainId, tElem.Name)
					if (tDictItemId <= 0) {
						set tSC = $$$ERROR($$$GeneralError, "WARNING: dictionary item '"_tElem.ItemURI_"' is referred in rule '"_tRuleDef.Name_"' and no longer present!")
					} else {
						set tDictItem = ##class(%iKnow.Objects.DictionaryItem).PKINDEXOpen(pDomainId, tDictItemId)
						set tElem.DictName = tDictItem.Dictionary.Name
					}
				}
				do tProxy.Elements.Insert(tElem)
			}
			do tJSON.RuleDefinitions.Insert(tProxy)
		}
		
		// nicen error, so we can at least try to recover
		if $$$ISERR(tSC) {
			set tJSON.ErrorNum = $system.Status.GetErrorCodes(tSC)
			set tJSON.ErrorMessage = $system.Status.GetErrorText(tSC)
			set tSC = $$$OK
		}
		
		do tJSON.%ToJSON(,..#JSONFORMATPARAMS)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit ..ErrorHandler(tSC)
}

ClassMethod UpdateRuleDef(pDomainId As %Integer) As %Status
{
	set tSC = $$$OK
	try {
		set tJSONString = ""
		while '%request.Content.AtEnd {
			set tJSONString = tJSONString_$zcvt(%request.Content.ReadLine(),"I","UTF8")
		}
		set tSC = ##class(%ZEN.Auxiliary.jsonProvider).%ConvertJSONToObject(tJSONString,,.tRequest)
		quit:$$$ISERR(tSC)
		
		
		if (tRequest.delete || tRequest.obj.ID) { // update = delete first
			set tSC = ##class(RuleDefinition).%DeleteId(tRequest.obj.ID)
			quit:$$$ISERR(tSC)
			if tRequest.delete {
				write "{}" // dummy output
				quit
			}
		}
		
		set tRuleDef = ##class(RuleDefinition).%New()
		set tRuleDef.DomainId = pDomainId
		set tRuleDef.Name = tRequest.obj.Name
		set tRuleDef.EnforceSequence = tRequest.obj.EnforceSequence
		set tRuleDef.Elements = ##class(%ListOfObjects).%New()
		for i = 1:1:tRequest.obj.Elements.Count() {
			set tRequestElem = tRequest.obj.Elements.GetAt(i)
			set tElem = ##class(RuleDefinitionElement).%New()
			set tElem.Type = $s(tRequestElem.ItemURI="ANY":"dictionary", 1:"item")
			set tElem.Name = $s(tRequestElem.ItemURI="ANY":tRequestElem.DictName, 1:tRequestElem.ItemURI)
			set tElem.Count = tRequestElem.Count
			set tElem.Negation = tRequestElem.Negation
			do tRuleDef.Elements.Insert(tElem)
		}
		
		set tSC = tRuleDef.%Save()
		quit:$$$ISERR(tSC)
		
		// dummy output
		write "{}" 
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit ..ErrorHandler(tSC)
}

ClassMethod GetFilterForRequestSet(pDomainId) As %iKnow.Filters.Filter [ Private ]
{
	quit:'$d(%request.Data("SourceFilter",1),tFilterSet) ""
	quit ""
}

/// Retrieves all sentences (including full text) in the domain containing <var>pEntity</var> and prints them as JSON
ClassMethod GetSentencesByEntity(pDomainId As %Integer, pEntity As %String = "") As %Status
{
	set tSC = $$$OK
	try {
		set:$data(%response) %response.ContentType="application/json"
		
		if $isobject(%request.Content) {
			set tJSONString = ""
			while '%request.Content.AtEnd {
				set tJSONString = tJSONString_$zcvt(%request.Content.ReadLine(),"I","UTF8")
			}
			set tSC = ##class(%ZEN.Auxiliary.jsonProvider).%ConvertJSONToObject(tJSONString,,.tRequest)
			quit:$$$ISERR(tSC)
			set:$isobject(tRequest.entity) pEntity = tRequest.entity.EntityValue
		}
		
		set tEntityId = ##class(%iKnow.Queries.EntityAPI).GetId(pDomainId, pEntity)
		set tHighlight("ENTITY", tEntityId) = "<b class=""entity"" title=""entity '"_$zcvt(pEntity,"O","HTML")_"'"">"
		
		set tSC = ##class(%iKnow.Queries.SentenceAPI).GetByEntities(.tSentences, pDomainId, pEntity, ..GetFilterForRequestSet(pDomainId), 1, ..#IKPAGESIZE)
		quit:$$$ISERR(tSC)
		
		set tJSON = ##class(%ZEN.proxyObject).%New()
		set tJSON.Sentences = ##class(%ListOfObjects).%New()
		set i = ""
		for {
			set i = $order(tSentences(i), 1, tSentData)
			quit:i=""
			set tSentId = $lg(tSentData,3)
			set tProxy = ##class(%ZEN.proxyObject).%New()
			set tProxy.SourceId = $lg(tSentData,1)
			set tProxy.ExternalId = $lg(tSentData,2)
			set tProxy.SentenceId = $lg(tSentData,3)
			set tProxy.Text = ..GetHighlightedSentence(pDomainId, tProxy.SentenceId, .tHighlight, .tSC)
			quit:$$$ISERR(tSC)
			
			do tJSON.Sentences.Insert(tProxy)
		}
		quit:$$$ISERR(tSC)
		
		do tJSON.%ToJSON(,..#JSONFORMATPARAMS)
		
    } catch (ex) {
        set tSC=ex.AsStatus()
    }
	quit ..ErrorHandler(tSC)
}

/// Retrieves a highlighted summary of the text in source <var>pSourceId</var>, optionally filtered to the
/// sentences containing <var>pFilterByEntity</var>. At most <var>pMaxSentences</var> will be returned.
/// Any markup in <var>pHighlight</var> is appended with default highlighting of negations
ClassMethod GetHighlightedSource(pDomainId As %Integer, pSourceId As %Integer, pFilterByEntity As %String = "", pMaxSentences As %Integer = 5, ByRef pHighlight, Output pSC As %Status = {$$$OK}) As %String
{
	set pSC = $$$OK, tString = ""
	try {
		
		// first select by entities
		if (pFilterByEntity'="") {
			set pHighlight("ENTITY", pFilterByEntity) = "<b class=""entity"" title=""entity '"_$zcvt(pFilterByEntity,"O","HTML")_"'"">"
			set pSC = ##class(%iKnow.Queries.SentenceAPI).GetByEntities(.tSentences, pDomainId, pFilterByEntity, $lb(pSourceId), 0)
			quit:$$$ISERR(pSC)
		} elseif $d(pHighlight("ENTITY")) {
			set tEntity = "", tEntityList=""
			for {
				set tEntity = $order(pHighlight("ENTITY",tEntity))
				quit:tEntity=""
				set tEntityList = tEntityList _ $lb(tEntity)
			}
			set pSC = ##class(%iKnow.Queries.SentenceAPI).GetByEntities(.tSentences, pDomainId, tEntityList, $lb(pSourceId), 0)
			quit:$$$ISERR(pSC)
		}
		set i = "", tSentIDs = ""
		for {
			set i = $order(tSentences(i),1,tSentData)
			quit:i=""
			set tSentIDs = tSentIDs _ $li(tSentData,3,3)
		}
		
		// now fetch the sentences of this source...
		// first selected by whether they are in tSentIDs, then based on summary relevance
		// and back in natural order
		set tSQL = "SELECT SentenceId, SummaryRelevance FROM %iKnow_Objects.Sentence WHERE DomainId = ? AND SourceId = ?"
		set tSQL = "SELECT TOP ? * FROM ("_tSQL_") ORDER BY CASE WHEN (SentenceId %INLIST ?) THEN 1 ELSE 0 END DESC, SummaryRelevance DESC"
		set tSQL = "SELECT * FROM ("_tSQL_") ORDER BY SentenceId ASC"
		set tStatement = ##class(%SQL.Statement).%New()
		set pSC = tStatement.%Prepare(tSQL)
		quit:$$$ISERR(pSC)
		set tResult = tStatement.%Execute(pMaxSentences, pDomainId, pSourceId, tSentIDs)
		
		
		set tSource = ##class(%iKnow.Objects.Source).PKINDEXOpen(pDomainId, pSourceId)
		set tPrevSentId = tSource.FirstSentenceId-1, tSentId=""
		while tResult.%Next() {
			set tSentId = tResult.%Get("SentenceId")
			
			set:(tPrevSentId'=(tSentId-1)) tString = tString_" ... "
			set tPrevSentId = tSentId
			
			set tString = tString _ ..GetHighlightedSentence(pDomainId, tSentId, .pHighlight, .pSC)
			quit:$$$ISERR(pSC)
		}
		if tSentId'=(tSource.FirstSentenceId+tSource.SentenceCount-1) {
			set tString = tString _ " ..."
		}
		
	} catch (ex) {
		set pSC = ex.AsStatus()
	}
	quit tString
}

ClassMethod GetHighlightedSentence(pDomainId As %Integer, pSentenceId As %Integer, ByRef pHighlight, Output pSC As %Status) As %String
{
	set pSC = $$$OK, tSentence = ""
	try {
		// default highlighting
		set tHighlight("ATTRIBUTE", $$$IKATTSENPOSITIVE) = "<span class=""sent-pos"">"
		set tHighlight("ATTRIBUTE", $$$IKATTSENNEGATIVE) = "<font class=""sent-neg"">"
		set tHighlight("ATTRIBUTE", $$$IKATTNEGATION) = "<u class=""negation"">"
		
		// append/override with explicit highlighting requirements
		merge tHighlight = pHighlight
		
		set tSentence = ##class(%iKnow.Queries.SentenceAPI).GetHighlighted(pDomainId, pSentenceId, .tHighlight,,, .pSC)
		
	} catch (ex) {
		set pSC = ex.AsStatus()
	}
	quit tSentence
}

/// Retrieves the top entities similar to <var>pString</var> and prints them to JSON
ClassMethod GetEntities(pDomainId As %Integer) As %Status
{
	set tSC = $$$OK
	try {
		set tJSONString = ""
		while '%request.Content.AtEnd {
			set tJSONString = tJSONString_$zcvt(%request.Content.ReadLine(),"I","UTF8")
		}
		set tSC = ##class(%ZEN.Auxiliary.jsonProvider).%ConvertJSONToObject(tJSONString,,.tRequest)
		quit:$$$ISERR(tSC)
		
		if $isobject(tRequest.blacklists) {
			set tBlacklists = ""
			for i = 1:1:tRequest.blacklists.Count() {
				set tBlacklists = tBlacklists_$lb(tRequest.blacklists.GetAt(i))
			}
		} else {
			set tBlacklists = ""
		}
		
		if (tRequest.entity = "") {
			set tSC = ##class(%iKnow.Queries.EntityAPI).GetTop(.tResult, pDomainId, 1, ..#IKPAGESIZE, ..GetFilter(pDomainId, tRequest.filter), ..#IKPFILTERMODE,,,, tBlacklists)
			quit:$$$ISERR(tSC)
		} else {
			set tSC = ##class(%iKnow.Queries.EntityAPI).GetSimilar(.tResult, pDomainId, tRequest.entity, 1, ..#IKPAGESIZE, ..GetFilter(pDomainId, tRequest.filter), ..#IKPFILTERMODE,, tBlacklists)
			quit:$$$ISERR(tSC)
		}
		
		set:$data(%response) %response.ContentType="application/json"
		set tJSON = ##class(%ZEN.proxyObject).%New()
		set tJSON.Seed = tRequest.entity

		set i = "", tJSON.Entities = ##class(%ListOfObjects).%New()
		for {
			set i = $order(tResult(i), 1, tData)
			quit:i=""
			
			set tProxy = ##class(%ZEN.proxyObject).%New()
			set tProxy.EntityValue = $lg(tData,2)
			set tProxy.Frequency = $lg(tData,3)
			set tProxy.Spread = $lg(tData,4)
			
			if (tRequest.getMatches) {
				set tProxy.Matches = ##class(%ListOfObjects).%New()
				set tSC = ##class(%iKnow.Matching.MatchingAPI).GetDictionaryMatchesById(.tMatches, pDomainId, $lg(tData,1),, 0, 0)
				quit:$$$ISERR(tSC)
				set j = "", tProxy.HighestScore = 0
				for {
					set j = $order(tMatches(j),1,tMatchData)
					quit:j=""
					
					set tMatch = ##class(%ZEN.proxyObject).%New()
					set tMatch.Dict = $lg(tMatchData,1)
					set tMatch.Score = $lg(tMatchData,8)
					do tProxy.Matches.Insert(tMatch)
					set:tProxy.HighestScore<tMatch.Score tProxy.HighestScore = tMatch.Score
				}
			}
			
			do tJSON.Entities.Insert(tProxy)
		}
		
		do tJSON.%ToJSON(,..#JSONFORMATPARAMS)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit ..ErrorHandler(tSC)
}

ClassMethod GetFilter(pDomainId As %Integer, pFilterSpec As %String = "") As %iKnow.Filters.Filter
{
	quit ""
}

/// Simple error handler, converting a <class>%Status</class> object to a JSON representation.
ClassMethod ErrorHandler(Stat As %Status) As %Status [ Private ]
{
	if $$$ISERR(Stat) {
		set errorcode=$piece(##class(%SYSTEM.Status).GetErrorCodes(Stat),",")
		set errormessage=##class(%SYSTEM.Status).GetOneStatusText(Stat)
		set errobj=##class(%ZEN.proxyObject).%New()
		set errobj.ErrorNum=errorcode
		set errobj.ErrorMessage=errormessage
		Set %response.ContentType="application/json"
		Do ##class(%ZEN.Auxiliary.jsonProvider).%ObjectToJSON(errobj)
		set errobj=""
	}
	quit $$$OK
}

ClassMethod GetDictionaries(pDomainId As %Integer) As %Status
{
	set tSC = $$$OK
	try {
		set tJSON = ##class(%ZEN.proxyObject).%New()
		
		set tJSON.dictionaries = ##class(%ListOfObjects).%New()
		set tSC = ##class(%iKnow.Matching.DictionaryAPI).GetDictionaries(.tDicts, pDomainId, 0, 0)
		quit:$$$ISERR(tSC)
		set i = ""
		for {
			set i = $order(tDicts(i), 1, tDictData)
			quit:i=""
			
			set tDict = ##class(%ZEN.proxyObject).%New()
			set tDict.id = $lg(tDictData,1)
			set tDict.name = $lg(tDictData,2)
			set tDict.items = ##class(%ListOfObjects).%New()
			do tJSON.dictionaries.Insert(tDict)
			
			set tSC = ##class(%iKnow.Matching.DictionaryAPI).GetDictionaryItems(.tItems, pDomainId, tDict.id, 0, 0)
			quit:$$$ISERR(tSC)
			set j = ""
			for {
				set j = $order(tItems(j),1,tItemData)
				quit:j=""
				
				set tItem = ##class(%ZEN.proxyObject).%New()
				set tItem.id = $lg(tItemData,1)
				set tItem.name = $lg(tItemData,2)
				set tItem.uri = $lg(tItemData,3)
				set tItem.terms = ##class(%ListOfObjects).%New()
				do tDict.items.Insert(tItem)
				
				set tSC = ##class(%iKnow.Matching.DictionaryAPI).GetDictionaryTermsByItem(.tTerms, pDomainId, tItem.id, 0, 0)
				quit:$$$ISERR(tSC)
				set k = ""
				for {
					set k = $order(tTerms(k), 1, tTermData)
					quit:k=""
					
					set tTerm = ##class(%ZEN.proxyObject).%New()
					set tTerm.id = $lg(tTermData,1)
					set tTerm.string = $lg(tTermData,2)
					do tItem.terms.Insert(tTerm)
				}
			}
		}
		do tJSON.%ToJSON(,..#JSONFORMATPARAMS)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit ..ErrorHandler(tSC)
}

ClassMethod GetBlacklists(pDomainId As %Integer) As %Status
{
	set tSC = $$$OK
	try {
		set tJSON = ##class(%ZEN.proxyObject).%New()
		
		set tJSON.blacklists = ##class(%ListOfObjects).%New()
		set tSC = ##class(%iKnow.Utils.MaintenanceAPI).GetBlackLists(.tResult, pDomainId)
		quit:$$$ISERR(tSC)
		set i = ""
		for {
			set i = $order(tResult(i), 1, tData)
			quit:i=""
			
			set tBL = ##class(%ZEN.proxyObject).%New()
			set tBL.id = $lg(tData,1)
			set tBL.name = $lg(tData,2)
			set tBL.entries = ##class(%ListOfDataTypes).%New()
			do tJSON.blacklists.Insert(tBL)
			
			set tSC = ##class(%iKnow.Utils.MaintenanceAPI).GetBlackListElements(.tItems, pDomainId, tBL.id)
			quit:$$$ISERR(tSC)
			set j = ""
			for {
				set j = $order(tItems(j),1,tItemData)
				quit:j=""
				
				do tBL.entries.Insert($lg(tItemData,2))
			}
		}
		
		do tJSON.%ToJSON(,..#JSONFORMATPARAMS)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit ..ErrorHandler(tSC)
}

ClassMethod UpdateDictionaries(pDomainId As %Integer) As %Status
{
	set tSC = $$$OK
	try {
		set tJSONString = ""
		while '%request.Content.AtEnd {
			set tJSONString = tJSONString_$zcvt(%request.Content.ReadLine(),"I","UTF8")
		}
		set tSC = ##class(%ZEN.Auxiliary.jsonProvider).%ConvertJSONToObject(tJSONString,,.tRequest)
		quit:$$$ISERR(tSC)
		
		if $isobject(tRequest.dictionaries) {
			for i = 1:1:tRequest.dictionaries.Count() {
				set tDict = tRequest.dictionaries.GetAt(i)
				if (tDict.id) {
					set tDictObj = ##class(%iKnow.Objects.Dictionary).PKINDEXOpen(pDomainId, tDict.id)
					if '$isobject(tDictObj) {
						set tDict.id = ""
					} elseif (tDictObj.Name'=tDict.name) {
						set tSC = ##class(%iKnow.Matching.DictionaryAPI).DropDictionary(pDomainId, tDict.id)
						quit:$$$ISERR(tSC)
						set tDict.id = ""
					}
				}
				if 'tDict.id {
					set tDict.id = ##class(%iKnow.Matching.DictionaryAPI).CreateDictionary(pDomainId, tDict.name,,,, .tSC)
					quit:$$$ISERR(tSC)
				}
				set tDicts(tDict.id)=""
				
				kill tItems
				if $isobject(tDict.items) {
					for j = 1:1:tDict.items.Count() {
						set tItem = tDict.items.GetAt(j)
						if (tItem.id) {
							set tItemObj = ##class(%iKnow.Objects.DictionaryItem).PKINDEXOpen(pDomainId, tItem.id)
							if '$isobject(tItemObj) {
								set tItem.id = ""
							} elseif (tItem.name'=tItemObj.Name) || (tItem.uri'=tItemObj.URI) {
								set tSC = ##class(%iKnow.Matching.DictionaryAPI).DropDictionaryItem(pDomainId, tItem.id)
								quit:$$$ISERR(tSC)
								set tItem.id = ""
							}
						}
						if 'tItem.id {
							set tItem.id = ##class(%iKnow.Matching.DictionaryAPI).CreateDictionaryItem(pDomainId, tDict.id, tItem.name, tItem.uri,, .tSC)
							quit:$$$ISERR(tSC)
						}
						set tItems(tItem.id)=""
						
						// Terms
						if $isobject(tItem.terms) {
							for k = 1:1:tItem.terms.Count() {
								set tTerm = tItem.terms.GetAt(k)
								if (tTerm.id) {
									set tTermObj = ##class(%iKnow.Objects.DictionaryTerm).PKINDEXOpen(pDomainId, tTerm.id)
									if '$isobject(tTermObj) {
										set tTerm.id = ""
									} elseif (tTerm.string'=tTermObj.String) {
										set tSC = ##class(%iKnow.Matching.DictionaryAPI).DropDictionaryTerm(pDomainId, tTerm.id)
										quit:$$$ISERR(tSC)
										set tTerm.id = ""
									}
								}
								if 'tTerm.id {
									set tTerm.id = ##class(%iKnow.Matching.DictionaryAPI).CreateDictionaryTerm(pDomainId, tItem.id, tTerm.string,, .tSC)
									quit:$$$ISERR(tSC)
								}
								set tTerms(tTerm.id) = ""
							}
							quit:$$$ISERR(tSC)
							
							// kill removed terms: 
							set tSC = ##class(%iKnow.Matching.DictionaryAPI).GetDictionaryTermsByItem(.tAllTerms, pDomainId, tItem.id, 0, 0)
							quit:$$$ISERR(tSC)
							set k = ""
							for {
								set k = $order(tAllTerms(k),1,tTermData)
								quit:k=""
								
								set tDictTermId = $lg(tTermData,1)
								continue:$d(tTerms(tDictTermId))
								set tSC = ##class(%iKnow.Matching.DictionaryAPI).DropDictionaryTerm(pDomainId, tDictTermId)
								quit:$$$ISERR(tSC)
							}
							quit:$$$ISERR(tSC)
						}
						
					}
					quit:$$$ISERR(tSC)
					
					
					// kill removed items: 
					set tSC = ##class(%iKnow.Matching.DictionaryAPI).GetDictionaryItems(.tAllItems, pDomainId, tDict.id, 0, 0)
					quit:$$$ISERR(tSC)
					set j = ""
					for {
						set j = $order(tAllItems(j),1,tItemData)
						quit:j=""
						
						set tDictItemId = $lg(tItemData,1)
						continue:$d(tItems(tDictItemId))
						set tSC = ##class(%iKnow.Matching.DictionaryAPI).DropDictionaryItem(pDomainId, tDictItemId)
						quit:$$$ISERR(tSC)
					}
					quit:$$$ISERR(tSC)
				}
			}
			quit:$$$ISERR(tSC)
		}
		
		// kill removed dicts 
		set tSC = ##class(%iKnow.Matching.DictionaryAPI).GetDictionaries(.tAllDicts, pDomainId, 0, 0)
		quit:$$$ISERR(tSC)
		set i = ""
		for {
			set i = $order(tAllDicts(i),1,tDictData)
			quit:i=""
			
			set tDictId = $lg(tDictData,1)
			continue:$d(tDicts(tDictId))
			set tSC = ##class(%iKnow.Matching.DictionaryAPI).DropDictionary(pDomainId, tDictId)
			quit:$$$ISERR(tSC)
		}
		quit:$$$ISERR(tSC)
		
		
		// job off matching of entity uniques and sources
		job ##class(%iKnow.Matching.MatchingAPI).MatchSources(pDomainId)
		
		
		if $isobject(tRequest.blacklists) {
			for i = 1:1:tRequest.blacklists.Count() {
				set tBL = tRequest.blacklists.GetAt(i)
				if (tBL.id) {
					set tBLObj = ##class(%iKnow.Objects.BlackList).PKINDEXOpen(pDomainId, tBL.id)
					if '$isobject(tBLObj) {
						set tBL.id =""
					} elseif (tBLObj.Name '= tBL.name) {
						do ##class(%iKnow.Utils.MaintenanceAPI).DropBlackList(pDomainId, tBL.id)
						set tBL.id=""
					}
				}
				if (tBL.id) {
					do ##class(%iKnow.Utils.MaintenanceAPI).ClearBlackList(pDomainId, tBL.id)
				} else {
					set tBL.id = ##class(%iKnow.Utils.MaintenanceAPI).CreateBlackList(pDomainId, tBL.name,, .tSC)
					quit:$$$ISERR(tSC)
				}
				
				for j = 1:1:tBL.entries.Count() {
					do ##class(%iKnow.Utils.MaintenanceAPI).AddStringToBlackList(pDomainId, tBL.id, tBL.entries.GetAt(j))
				}
				
				set tBLIds(tBL.id)=""
			}
			quit:$$$ISERR(tSC)
		}
		
		
		// kill removed blacklists 
		set tSC = ##class(%iKnow.Utils.MaintenanceAPI).GetBlackLists(.tAllBL, pDomainId, 0)
		quit:$$$ISERR(tSC)
		set i = ""
		for {
			set i = $order(tAllBL(i),1,tData)
			quit:i=""
			
			set tBLID = $lg(tData,1)
			continue:$d(tBLIds(tBLID))
			set tSC = ##class(%iKnow.Utils.MaintenanceAPI).DropBlackList(pDomainId, tBLID)
			quit:$$$ISERR(tSC)
		}
		quit:$$$ISERR(tSC)
		
		write "{}" // dummy output
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit ..ErrorHandler(tSC)
}

ClassMethod GetSources(pDomainId As %Integer) As %Status
{
	set tSC = $$$OK
	try {
		
		set tFilter = ##class(%iKnow.Filters.SimpleMetadataFilter).%New(pDomainId, "DocumentName", "IS NULL")
		set tSC = ##class(%iKnow.Queries.SourceAPI).GetByDomain(.tSources, pDomainId, 1, 100, tFilter)
		quit:$$$ISERR(tSC)
		
		set tJSON = ##class(%ZEN.proxyObject).%New()
		set tJSON.sources = ##class(%ListOfObjects).%New()
		
		set i = ""
		for {
			set i = $order(tSources(i), 1, tSrcData) 
			quit:i=""
			
			set tSource = ##class(%ZEN.proxyObject).%New()
			set tSource.sourceId = $lg(tSrcData,1)
			set tSource.externalId = $lg(tSrcData,2)
			do tJSON.sources.Insert(tSource)
		}
		
		do tJSON.%ToJSON(,..#JSONFORMATPARAMS)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit ..ErrorHandler(tSC)
}

ClassMethod GetSourceText(pDomainId As %Integer, pSourceId As %Integer) As %Status
{
	set tSC = $$$OK
	try {
		
		// set tSource = ##class(%iKnow.Objects.Source).PKINDEXOpen(pDomainId, pSourceId,, .tSC)
		set tSC = ##class(%iKnow.Queries.SentenceAPI).GetBySource(.tSentences, pDomainId, pSourceId, 0, 0)
		quit:$$$ISERR(tSC)
		set tText="", i=""
		for {
			set i = $order(tSentences(i),1,tSentData)
			quit:i=""
			
			set tText = tText_$s(tText="":"",1:$c(13,10,13,10))_$lg(tSentData,2)
		}
		
		set tJSON = ##class(%ZEN.proxyObject).%New()
		set tJSON.text = tText
		quit:$$$ISERR(tSC)
		
		do tJSON.%ToJSON(,..#JSONFORMATPARAMS)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit ..ErrorHandler(tSC)
}

}

