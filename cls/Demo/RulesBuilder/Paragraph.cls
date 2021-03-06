Class Demo.RulesBuilder.Paragraph Extends %Persistent
{

Property DocumentName As %String(MAXLEN = 250);

Property StartPos As %Integer;

Property EndPos As %Integer;

Property StartLine As %Integer;

Property EndLine As %Integer;

Property Key As %String;

Property Parent As Paragraph;

Property TextContents As %String(MAXLEN = "");

Property FullKey As %String [ Calculated, SqlComputeCode = { new p set p = ##class(Demo.RulesBuilder.Paragraph).%OpenId({Parent}), {*} = $s($isobject(p)&&(p.Key'=""):p.FullKey_".", 1:"") _ {Key}}, SqlComputed ];

Property Level As %Integer [ Calculated, SqlComputeCode = { new p set p = ##class(Demo.RulesBuilder.Paragraph).%OpenId({Parent}), {*} = $s($isobject(p):p.Level, 1:0) +1}, SqlComputed ];

Property FullTextContents As %Integer [ Calculated, SqlComputeCode = { set {*} = ##class(Demo.RulesBuilder.Paragraph).GetFullText({ID})}, SqlComputed ];

Index DocumentIdx On DocumentName;

ClassMethod GetFullText(pParagraphID As %Integer, pLevelsUp As %Integer = 1) As %String [ SqlProc ]
{
	set tPar = ..%OpenId(pParagraphID)
	set tText = tPar.TextContents
	if (pLevelsUp'=0) && $isobject(tPar.Parent) {
		set tText = ..GetFullText(tPar.Parent.%Id(), pLevelsUp-1)_$c(13,10)_tText
	}
	quit tText
}

Method ToProxy(pDomainId As %Integer = 0, ByRef pMarkup, pLevelsUp As %Integer = 1) As %ZEN.proxyObject
{
	set tProxy = ##class(%ZEN.proxyObject).%New()
	set tProxy.paragraphId = ..%Id()
	set tProxy.documentName = ..DocumentName
	set tProxy.startPos = ..StartPos
	set tProxy.key = ..Key
	set tProxy.fullKey = ..FullKey
	set tProxy.fullText = ..FormatText(pDomainId, .pMarkup, pLevelsUp)
	quit tProxy
}

Method FormatText(pDomainId As %Integer = 0, ByRef pMarkup, pLevelsUp As %Integer = 1, pFormatLevels As %Integer = 2) As %ZEN.proxyObject
{
	quit:..TextContents="" ""
	set tSC = $$$OK, tText=""
	try {
		if 'pFormatLevels {
			set tText = "<p style=""margin-left:"_((..Level-1)*10)_"px; color: #999999;"">"_$zstrip(..TextContents,"<>WC")_"</p>"
			set:$isobject(..Parent)&&(pLevelsUp'=0) tText = ..Parent.FormatText(pDomainId,.pMarkup,pLevelsUp-1, $s(pFormatLevels:pFormatLevels-1, 1:0))_$c(13,10)_tText
			quit
		} elseif 'pDomainId {
			set tString = $system.iKnow.Highlight(..TextContents, .tHighlight)
		} else {
			set tString=""
			set tDomainName = $system.iKnow.GetDomainName(pDomainId)
			set tSC = $system.iKnow.IndexString(tDomainName, "temp", ..TextContents,, 1, .vSrcId)
			quit:$$$ISERR(tSC)
			if $d(pMarkup("MATCH")) || $d(pMarkup("MATCHITEM")) {
				set tSC = ##class(%iKnow.Matching.MatchingAPI).MatchSource(pDomainId, vSrcId)
				quit:$$$ISERR(tSC)
			}
			set tSentCount = ##class(%iKnow.Queries.SentenceAPI).GetCountBySource(pDomainId, vSrcId, .tSC)
			quit:$$$ISERR(tSC)
			set tString=""
			for i = 1:1:tSentCount {
				set:i>1 tString = tString_" "
				set tString = tString _ "<span id=""par-"_..%Id()_"-sent-"_i_""">" _ ##class(%iKnow.Queries.SentenceAPI).GetHighlighted(pDomainId, i, .pMarkup, vSrcId,, .tSC) _ "</span>"
				quit:$$$ISERR(tSC)
			}
			quit:$$$ISERR(tSC)
			do $system.iKnow.DeleteVirtualSource(tDomainName, vSrcId)
		}
			
		set tText = "<p style=""margin-left:"_((..Level-1)*10)_"px;"">"_tString_"</p>"
		set:$isobject(..Parent)&&(pLevelsUp'=0) tText = ..Parent.FormatText(pDomainId,.pMarkup,pLevelsUp-1, $s(pFormatLevels:pFormatLevels-1, 1:0))_$c(13,10)_tText
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	if $$$ISERR(tSC) { $$$ThrowStatus(tSC) }
	quit tText
}

ClassMethod LoadFromString(pText As %String, ByRef pDocName As %String, pEraseExisting As %Boolean = 1) As %Status
{
	set tSC = $$$OK
	try {
		if ($g(pDocName)="") {
			set pDocName = $zdt($h)
		}
		
		if pEraseExisting {
			&SQL(DELETE FROM Demo_RulesBuilder.Paragraph WHERE DocumentName = :pDocName)
		}
		
		set tSC = ..ParseString(.tObject, pText, pDocName)
		quit:$$$ISERR(tSC)
		
		set tSC = ..SaveFromProxy(tObject)
		quit:$$$ISERR(tSC)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit tSC
}

ClassMethod ParseString(Output pObject, pText As %String, pDocName As %String = "", pLineTerminator As %String = "") As %Status
{
	set tSC = $$$OK
	try {
		
		if pLineTerminator="" {
			set tLineTerminator = ##class(%Stream.FileCharacter).%New().LineTerminator
		} else {
			set tLineTerminator = pLineTerminator
		}
		set tLineTerminatorLength = $l(tLineTerminator), tPos=0
		
		do {
			set tNewPos = $find(pText,tLineTerminator,tPos)
			set tArray($i(tArray),"p") = tPos
			if tNewPos {
				set tArray(tArray) = $e(pText,tPos,tNewPos-tLineTerminatorLength)
			} else {
				set tArray(tArray) = $e(pText,tPos,*)
			}
			set tPos = tNewPos
		} while tPos
		
		set tSC = ..ProcessTextArray(.tArray, .pDocName, .pObject, tLineTerminator)
		quit:$$$ISERR(tSC)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit tSC
}

ClassMethod LoadFromFile(pPath As %String = "C:\Users\bdeboe\Documents\data\financial\20151123 IMAs\IMA Sample 1_Confidential.txt", pEraseExisting As %Boolean = 1) As %Status
{
	set tSC = $$$OK
	try {
		if pEraseExisting {
			&SQL(DELETE FROM Demo_RulesBuilder.Paragraph WHERE DocumentName = :pPath)
		}
		
		set tFile = ##class(%Stream.FileCharacter).%New()
		set tSC = tFile.LinkToFile(pPath)
		quit:$$$ISERR(tSC)
		
		set tLineTerminator = tFile.LineTerminator, tLineTerminatorLength = $l(tLineTerminator), tPos=0
		
		while 'tFile.AtEnd {
			set tOriginal($i(tOriginal),"p") = tPos
			set tOriginal(tOriginal) = tFile.ReadLine()
			set tPos = tPos+$l(tOriginal(tOriginal))+tLineTerminator
		}
		set tFile=""
		
		set tSC = ..ProcessTextArray(.tOriginal, pPath, .tObject, tLineTerminator)
		quit:$$$ISERR(tSC)
		
		set tSC = ..SaveFromProxy(tObject)
		quit:$$$ISERR(tSC)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit tSC
}

ClassMethod SaveFromProxy(pObject As %ZEN.proxyObject) As %Status
{
	set tSC = $$$OK
	try {
		
		set tSC = ..SaveOneProxy(pObject, pObject.documentName)
		quit:$$$ISERR(tSC)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit tSC
}

ClassMethod SaveOneProxy(pObject As %ZEN.proxyObject, pDocName As %String, pParent As Paragraph = "") As %Status [ Internal, Private ]
{
	set tParagraph = ..%New()
	set tParagraph.DocumentName = pDocName
	set tParagraph.Key = pObject.key
	set tParagraph.TextContents = pObject.text
	set tParagraph.StartLine = pObject.startLine
	set tParagraph.EndLine = pObject.endLine
	set tParagraph.StartPos = pObject.startPos
	set tParagraph.EndPos = pObject.endPos
	set tParagraph.Parent = pParent
	set tSC = tParagraph.%Save()
	quit:$$$ISERR(tSC) tSC
	
	quit:'$isobject(pObject.children) tSC
	for i = 1:1:pObject.children.Count() {
		set tSC = ..SaveOneProxy(pObject.children.GetAt(i), pDocName, tParagraph)
		quit:$$$ISERR(tSC)
	}
	quit tSC
}

ClassMethod ProcessTextArray(ByRef pLineArray, pDocName As %String, Output pObject As %ZEN.proxyObject, pLineTerminator As %String = "") As %Status
{
	set tSC = $$$OK
	try {
		set pObject = ##class(%ZEN.proxyObject).%New()
		set pObject.documentName = pDocName
		
		if pLineTerminator="" {
			set tLineTerminator = ##class(%Stream.FileCharacter).%New().LineTerminator
		} else {
			set tLineTerminator = pLineTerminator
		}
		set tLineTerminatorLength = $l(tLineTerminator)
		
		set tKeyStyles("1") = $lb("numbers",$lb("1","2","3","4","5","6","7","8","9","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24","25","26"),"ilI","111")
		set tKeyStyles("a") = $lb("numbers",$lb("a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"),"liIra1","illfbl",$lb($lb("cl","d")))
		set tKeyStyles("A") = $lb("numbers",$lb("A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"),"1","I")
		set tKeyStyles("i") = $lb("numbers",$lb("i","ii","iii","iv","v","vi","vii","viii","ix","x","xi","xii","xiii","xiv","xv","xvi","xvii","xviii","xix","xx","xxi","xxii","xxiii","xxiv","xxv"),"1lIVtXL","iiivixi",$lb($lb(" ",""),$lb("n","ii"),$lb("m","iii")))
		set tKeyStyles("I") = $lb("numbers",$lb("I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII","XIII","XIV","XV","XVI","XVII","XVIII","XIX","XX","XXI","XXII","XXIII","XXIV","XXV"),"1lvx","IIVX",$lb($lb(" ","")))
		set tKeyStyles("*") = $lb("bullets","*")
		set tKeyStyles("-") = $lb("bullets","-")
		
		
		// tKeyStack( [current level] ) = $lb( [key style], [key style info/pos] )
		// tKeyStack( [current level], "obj" ) = [last obj on this level]
		set tLineNumber = 0, tText="", tKey="", tKeyStack=0, tStartLine=0, tStartPos=0
		while $i(tLineNumber)<=pLineArray {
			
			// consider empty lines as paragraph ending
			if $zstrip((pLineArray(tLineNumber)),"*CW")="" {
				
				do AppendParagraph()
				
				set tStartLine = tLineNumber+1
				set tStartPos = tStartPos+tLineTerminatorLength
				continue
			}
			
			set tStart = $zstrip(pLineArray(tLineNumber),"<WC")
			
			// check if it's the next key for anything already on tKeyStack
			for tStackPos = tKeyStack:-1:1 {
				set tStackStyle = tKeyStack(tStackPos)
				continue:$lg(tStackStyle)=""
				
				if '$$CheckStyle(tStart, .tStackStyle, .tNewKey) {
					
					// if this isn't the first of its style, check if there's any predictable
					// OCR issues at play
					set tStackStyle = tKeyStack(tStackPos)
					if ($lg(tStackStyle)'="") && $d(tKeyStyles($lg(tStackStyle)),tStyleInfo) && ($lg(tStyleInfo,1)="numbers") && ($lg(tStackStyle,2)>0) {
						set tSomewhatFixed = tStart
						if $ld(tStyleInfo,5,tReplaceList) {
							set ptr=0
							while $listnext(tReplaceList,ptr,tReplace) {
								set tSomewhatFixed = $replace(tSomewhatFixed,$li(tReplace),$li(tReplace,2))
							}
						}
						set tSomewhatFixed = $translate(tSomewhatFixed,$lg(tStyleInfo,3),$lg(tStyleInfo,4))
						continue:'$$CheckStyle(tSomewhatFixed, .tStackStyle, .tNewKey)
					} else {
						continue
					}
				}
				
				do AppendParagraph()
				
				// if we went up a level, update tKeyStack
				for i = tStackPos+1:1:tKeyStack {
					kill tKeyStack(i)
				}
				set tKeyStack=tStackPos
				set tKeyStack(tStackPos) = tStackStyle
				
				set tKey = tNewKey
				goto proceed
			}
			
			
			// otherwise, check whether we're starting a new key style
			set i = ""
			for {
				set i = $order(tKeyStyles(i))
				quit:i=""
				set tNewStyle = $lb(i)
				continue:'$$CheckStyle(tStart, .tNewStyle, .tNewKey)
				
				do AppendParagraph()
				
				// update tKeyStack
				set tKeyStack($i(tKeyStack)) = tNewStyle
				
				set tKey = tNewKey
				goto proceed
			}
			
			// as a final test, check if we perhaps skipped a single position
			
			for tStackPos = tKeyStack:-1:1 {
				set tStackStyle = tKeyStack(tStackPos)
				continue:$lg(tStackStyle)=""
				set $li(tStackStyle,2) = $lg(tStackStyle,2)+1
				continue:'$$CheckStyle(tStart, .tStackStyle, .tNewKey)
				do AppendParagraph()
				
				// if we went up a level, update tKeyStack
				for i = tStackPos+1:1:tKeyStack {
					kill tKeyStack(i)
				}
				set tKeyStack=tStackPos
				set tKeyStack(tStackPos) = tStackStyle
				
				set tKey = tNewKey
				goto proceed
			}
			
			
			// still nothing found, so just append to previous paragraph
			set tText = tText _ $s(tText="":"", 1:tLineTerminator) _ pLineArray(tLineNumber)
proceed
		}
		quit:$$$ISERR(tSC)
		
		do AppendParagraph(1)
		
	} catch (ex) {
		set tSC = ex.AsStatus()
	}
	quit tSC
	
CheckStyle(tString, &tStyleInfo, &tKey)
	set tStyle = $lg(tStyleInfo)
	if $lg(tKeyStyles(tStyle),1)="numbers" {
		
		set tPosInStyle = $lg(tStyleInfo,2)+1
	
		// quick check of first char
		/*if (tPosInStyle=1) && ($e(tString)'=tStyle) { 
			return 0
		}*/
		
		set tKey = $lg($lg(tKeyStyles(tStyle),2),tPosInStyle)
		for tSep = "."," ",")",$c(9),"·",":" {
			set tKeyString = tKey_tSep
			if $e(tString,1,$l(tKeyString))=tKeyString {
				
				// special case: when we're looking at "i." or "1.", it's worth checking the next
				// line too as this is a common OCR issue
				if (tPosInStyle=1) && ((tStyle="i") || (tStyle="1")) {
					for l=1:1:3 {
						set tNextLine = $zstrip($g(pLineArray(tLineNumber+l)),"<WC")
						quit:tNextLine'=""
					}
					if (tStyle="i") && ($e(tNextLine,1,$l(tKeyString))=("1"_tSep)) {
						set tStyle="1", tKey="1"
					} elseif (tStyle="1") && (($e(tNextLine,1,$l(tKeyString)+1)=("ii"_tSep)) || ($e(tNextLine,1,$l(tKeyString)+1)=("11"_tSep))) {
						set tStyle="i", tKey="i"
					}
				}
				
				set tStyleInfo = $lb(tStyle, tPosInStyle)
				return 1
			}
		}
	} elseif $lg(tKeyStyles(tStyle),1)="bullets" {
		
		set tBullet = $lg(tKeyStyles(tStyle),2)
		for tSep = " ",$c(9) {
			if $e(tString, 1, $l(tBullet)+1)=(tBullet_tSep) {
				set tStyleInfo = $lb(tStyle, $lg(tStyleInfo,2)+1)
				return 1
			}
		}
		
	} else { 
		// not implemented
	}
	set tStyleInfo="", tKey=""
	quit 0
	
AppendParagraph(tIsFinal=0)
	if ($zstrip(tText,"*WC")'="") {
		set tParagraph = ##class(%ZEN.proxyObject).%New()
		set tParagraph.key = tKey
		set tParagraph.text = tText
		set tParagraph.startLine = tStartLine
		set tParagraph.endLine = tLineNumber-1
		set tParagraph.startPos = tStartPos
		set tParagraph.endPos = tStartPos+$l(tText)
		
		set:'$d(tKeyStack(tKeyStack-1,"obj"),tParent) tParent = pObject
		set:'$isobject(tParent.children) tParent.children = ##class(%ListOfObjects).%New()
		do tParent.children.Insert(tParagraph)
		
		set tKeyStack(tKeyStack,"obj") = tParagraph
	}
	if 'tIsFinal {
		set tStartLine = tLineNumber
		set tStartPos = pLineArray(tLineNumber,"p")
		set tText=pLineArray(tLineNumber)
	}
}

Storage Default
{
<Data name="ParagraphDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>DocumentName</Value>
</Value>
<Value name="3">
<Value>StartPos</Value>
</Value>
<Value name="4">
<Value>EndPos</Value>
</Value>
<Value name="5">
<Value>StartLine</Value>
</Value>
<Value name="6">
<Value>EndLine</Value>
</Value>
<Value name="7">
<Value>Key</Value>
</Value>
<Value name="8">
<Value>Parent</Value>
</Value>
<Value name="9">
<Value>TextContents</Value>
</Value>
</Data>
<DataLocation>^Demo.RulesBuilder.ParagraphD</DataLocation>
<DefaultData>ParagraphDefaultData</DefaultData>
<IdLocation>^Demo.RulesBuilder.ParagraphD</IdLocation>
<IndexLocation>^Demo.RulesBuilder.ParagraphI</IndexLocation>
<StreamLocation>^Demo.RulesBuilder.ParagraphS</StreamLocation>
<Type>%Library.CacheStorage</Type>
}

}

