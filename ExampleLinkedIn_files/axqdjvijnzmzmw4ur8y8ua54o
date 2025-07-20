!function(t){"object"==typeof module&&module.exports?(t.default=t,module.exports=t):"function"==typeof define&&define.amd?define("highcharts/modules/accessibility",["highcharts"],(function(e){t(e)
t.Highcharts=e
return t})):t("undefined"!=typeof Highcharts?Highcharts:void 0)}((function(t){function e(t,e,i,n){t.hasOwnProperty(e)||(t[e]=n.apply(null,i))}e(t=t?t._modules:{},"Accessibility/Utils/HTMLUtilities.js",[t["Core/Globals.js"],t["Core/Utilities.js"]],(function(t,e){var i=t.doc,n=t.win,o=e.merge
return{addClass:function(t,e){t.classList?t.classList.add(e):0>t.className.indexOf(e)&&(t.className+=e)},escapeStringForHTML:function(t){return t.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;").replace(/'/g,"&#x27;").replace(/\//g,"&#x2F;")},getElement:function(t){return i.getElementById(t)},getFakeMouseEvent:function(t){if("function"==typeof n.MouseEvent)return new n.MouseEvent(t)
if(i.createEvent){var e=i.createEvent("MouseEvent")
if(e.initMouseEvent)return e.initMouseEvent(t,!0,!0,n,"click"===t?1:0,0,0,0,0,!1,!1,!1,!1,0,null),e}return{type:t}},getHeadingTagNameForElement:function(t){var e=function(t){t=parseInt(t.slice(1),10)
return"h"+Math.min(6,t+1)},i=function(t){var n
t:{for(n=t;n=n.previousSibling;){var o=n.tagName||""
if(/H[1-6]/.test(o)){n=o
break t}}n=""}if(n)return e(n)
if(!(t=t.parentElement))return"p"
n=t.tagName
return/H[1-6]/.test(n)?e(n):i(t)}
return i(t)},removeElement:function(t){t&&t.parentNode&&t.parentNode.removeChild(t)},reverseChildNodes:function(t){for(var e=t.childNodes.length;e--;)t.appendChild(t.childNodes[e])},setElAttrs:function(t,e){Object.keys(e).forEach((function(i){var n=e[i]
null===n?t.removeAttribute(i):t.setAttribute(i,n)}))},stripHTMLTagsFromString:function(t){return"string"==typeof t?t.replace(/<\/?[^>]+(>|$)/g,""):t},visuallyHideElement:function(t){o(!0,t.style,{position:"absolute",width:"1px",height:"1px",overflow:"hidden",whiteSpace:"nowrap",clip:"rect(1px, 1px, 1px, 1px)",marginTop:"-3px","-ms-filter":"progid:DXImageTransform.Microsoft.Alpha(Opacity=1)",filter:"alpha(opacity=1)",opacity:"0.01"})}}}))
e(t,"Accessibility/Utils/ChartUtilities.js",[t["Accessibility/Utils/HTMLUtilities.js"],t["Core/Utilities.js"]],(function(t,e){function i(t){var e,i
if(null!==(e=t.points)&&void 0!==e&&e.length)return null===(i=null==(t=s(t.points,(function(t){return!!t.graphic})))?void 0:t.graphic)||void 0===i?void 0:i.element}function n(t){var e=i(t)
return e&&e.parentNode||t.graph&&t.graph.element||t.group&&t.group.element}var o=t.stripHTMLTagsFromString,r=e.defined,s=e.find,a=e.fireEvent
return{getChartTitle:function(t){return o(t.options.title.text||t.langFormat("accessibility.defaultChartTitle",{chart:t}))},getAxisDescription:function(t){return t&&(t.userOptions&&t.userOptions.accessibility&&t.userOptions.accessibility.description||t.axisTitle&&t.axisTitle.textStr||t.options.id||t.categories&&"categories"||t.dateTime&&"Time"||"values")},getAxisRangeDescription:function(t){var e=t.options||{}
return e.accessibility&&void 0!==e.accessibility.rangeDescription?e.accessibility.rangeDescription:t.categories?(e=t.chart,t=t.dataMax&&t.dataMin?e.langFormat("accessibility.axis.rangeCategories",{chart:e,axis:t,numCategories:t.dataMax-t.dataMin+1}):""):!t.dateTime||0!==t.min&&0!==t.dataMin?function(t){var e,i,n=t.chart,o=(null===(i=null===(e=n.options)||void 0===e?void 0:e.accessibility)||void 0===i?void 0:i.screenReaderSection.axisRangeDateFormat)||""
e=function(e){return t.dateTime?n.time.dateFormat(o,t[e]):t[e]}
return n.langFormat("accessibility.axis.rangeFromTo",{chart:n,axis:t,rangeFrom:e("min"),rangeTo:e("max")})}(t):function(t){var e=t.chart,i={},n="Seconds"
i.Seconds=((t.max||0)-(t.min||0))/1e3
i.Minutes=i.Seconds/60
i.Hours=i.Minutes/60
i.Days=i.Hours/24;["Minutes","Hours","Days"].forEach((function(t){2<i[t]&&(n=t)}))
var o=i[n].toFixed("Seconds"!==n&&"Minutes"!==n?1:0)
return e.langFormat("accessibility.axis.timeRange"+n,{chart:e,axis:t,range:o.replace(".0","")})}(t)},getPointFromXY:function(t,e,i){for(var n,o=t.length;o--;)if(n=s(t[o].points||[],(function(t){return t.x===e&&t.y===i})))return n},getSeriesFirstPointElement:i,getSeriesFromName:function(t,e){return e?(t.series||[]).filter((function(t){return t.name===e})):t.series},getSeriesA11yElement:n,unhideChartElementFromAT:function t(e,i){i.setAttribute("aria-hidden",!1)
i!==e.renderTo&&i.parentNode&&(Array.prototype.forEach.call(i.parentNode.childNodes,(function(t){t.hasAttribute("aria-hidden")||t.setAttribute("aria-hidden",!0)})),t(e,i.parentNode))},hideSeriesFromAT:function(t){(t=n(t))&&t.setAttribute("aria-hidden",!0)},scrollToPoint:function(t){var e=t.series.xAxis,i=t.series.yAxis,n=null!=e&&e.scrollbar?e:i
if((e=null==n?void 0:n.scrollbar)&&r(e.to)&&r(e.from)){i=e.to-e.from
if(r(n.dataMin)&&r(n.dataMax)){var o=n.toPixels(n.dataMin),s=n.toPixels(n.dataMax)
t=(n.toPixels(t["xAxis"===n.coll?"x":"y"]||0)-o)/(s-o)}else t=0
e.updatePosition(t-i/2,t+i/2)
a(e,"changed",{from:e.from,to:e.to,trigger:"scrollbar",DOMEvent:null})}}}}))
e(t,"Accessibility/KeyboardNavigationHandler.js",[t["Core/Utilities.js"]],(function(t){function e(t,e){this.chart=t
this.keyCodeMap=e.keyCodeMap||[]
this.validate=e.validate
this.init=e.init
this.terminate=e.terminate
this.response={success:1,prev:2,next:3,noHandler:4,fail:5}}var i=t.find
e.prototype={run:function(t){var e=t.which||t.keyCode,n=this.response.noHandler,o=i(this.keyCodeMap,(function(t){return-1<t[0].indexOf(e)}))
o?n=o[1].call(this,e,t):9===e&&(n=this.response[t.shiftKey?"prev":"next"])
return n}}
return e}))
e(t,"Accessibility/Utils/DOMElementProvider.js",[t["Core/Globals.js"],t["Accessibility/Utils/HTMLUtilities.js"],t["Core/Utilities.js"]],(function(t,e,i){var n=t.doc,o=e.removeElement;(t=i.extend)((e=function(){this.elements=[]}).prototype,{createElement:function(){var t=n.createElement.apply(n,arguments)
this.elements.push(t)
return t},destroyCreatedElements:function(){this.elements.forEach((function(t){o(t)}))
this.elements=[]}})
return e}))
e(t,"Accessibility/Utils/EventProvider.js",[t["Core/Globals.js"],t["Core/Utilities.js"]],(function(t,e){var i=e.addEvent,n=function(){this.eventRemovers=[]};(e=e.extend)(n.prototype,{addEvent:function(){var e=i.apply(t,arguments)
this.eventRemovers.push(e)
return e},removeAddedEvents:function(){this.eventRemovers.forEach((function(t){t()}))
this.eventRemovers=[]}})
return n}))
e(t,"Accessibility/AccessibilityComponent.js",[t["Accessibility/Utils/ChartUtilities.js"],t["Accessibility/Utils/DOMElementProvider.js"],t["Accessibility/Utils/EventProvider.js"],t["Core/Globals.js"],t["Accessibility/Utils/HTMLUtilities.js"],t["Core/Utilities.js"]],(function(t,e,i,n,o,r){function s(){}var a=t.unhideChartElementFromAT,l=n.doc,c=n.win,u=o.removeElement,h=o.getFakeMouseEvent
t=r.extend
var d=r.fireEvent,p=r.merge
s.prototype={initBase:function(t){this.chart=t
this.eventProvider=new i
this.domElementProvider=new e
this.keyCodes={left:37,right:39,up:38,down:40,enter:13,space:32,esc:27,tab:9}},addEvent:function(){return this.eventProvider.addEvent.apply(this.eventProvider,arguments)},createElement:function(){return this.domElementProvider.createElement.apply(this.domElementProvider,arguments)},fireEventOnWrappedOrUnwrappedElement:function(t,e){var i=e.type
l.createEvent&&(t.dispatchEvent||t.fireEvent)?t.dispatchEvent?t.dispatchEvent(e):t.fireEvent(i,e):d(t,i,e)},fakeClickEvent:function(t){if(t){var e=h("click")
this.fireEventOnWrappedOrUnwrappedElement(t,e)}},addProxyGroup:function(t){this.createOrUpdateProxyContainer()
var e=this.createElement("div")
Object.keys(t||{}).forEach((function(i){null!==t[i]&&e.setAttribute(i,t[i])}))
this.chart.a11yProxyContainer.appendChild(e)
return e},createOrUpdateProxyContainer:function(){var t=this.chart,e=t.renderer.box
t.a11yProxyContainer=t.a11yProxyContainer||this.createProxyContainerElement()
e.nextSibling!==t.a11yProxyContainer&&t.container.insertBefore(t.a11yProxyContainer,e.nextSibling)},createProxyContainerElement:function(){var t=l.createElement("div")
t.className="highcharts-a11y-proxy-container"
return t},createProxyButton:function(t,e,i,n,o){var r=t.element,s=this.createElement("button"),l=p({"aria-label":r.getAttribute("aria-label")},i)
Object.keys(l).forEach((function(t){null!==l[t]&&s.setAttribute(t,l[t])}))
s.className="highcharts-a11y-proxy-button"
o&&this.addEvent(s,"click",o)
this.setProxyButtonStyle(s)
this.updateProxyButtonPosition(s,n||t)
this.proxyMouseEventsForButton(r,s)
e.appendChild(s)
l["aria-hidden"]||a(this.chart,s)
return s},getElementPosition:function(t){var e=t.element
return(t=this.chart.renderTo)&&e&&e.getBoundingClientRect?(e=e.getBoundingClientRect(),t=t.getBoundingClientRect(),{x:e.left-t.left,y:e.top-t.top,width:e.right-e.left,height:e.bottom-e.top}):{x:0,y:0,width:1,height:1}},setProxyButtonStyle:function(t){p(!0,t.style,{"border-width":0,"background-color":"transparent",cursor:"pointer",outline:"none",opacity:.001,filter:"alpha(opacity=1)","-ms-filter":"progid:DXImageTransform.Microsoft.Alpha(Opacity=1)",zIndex:999,overflow:"hidden",padding:0,margin:0,display:"block",position:"absolute"})},updateProxyButtonPosition:function(t,e){e=this.getElementPosition(e)
p(!0,t.style,{width:(e.width||1)+"px",height:(e.height||1)+"px",left:(e.x||0)+"px",top:(e.y||0)+"px"})},proxyMouseEventsForButton:function(t,e){var i=this
"click touchstart touchend touchcancel touchmove mouseover mouseenter mouseleave mouseout".split(" ").forEach((function(n){var o=0===n.indexOf("touch")
i.addEvent(e,n,(function(e){var n=o?i.cloneTouchEvent(e):i.cloneMouseEvent(e)
t&&i.fireEventOnWrappedOrUnwrappedElement(t,n)
e.stopPropagation()
e.preventDefault()}),{passive:!1})}))},cloneMouseEvent:function(t){if("function"==typeof c.MouseEvent)return new c.MouseEvent(t.type,t)
if(l.createEvent){var e=l.createEvent("MouseEvent")
if(e.initMouseEvent)return e.initMouseEvent(t.type,t.bubbles,t.cancelable,t.view||c,t.detail,t.screenX,t.screenY,t.clientX,t.clientY,t.ctrlKey,t.altKey,t.shiftKey,t.metaKey,t.button,t.relatedTarget),e}return h(t.type)},cloneTouchEvent:function(t){var e=function(t){for(var e=[],i=0;i<t.length;++i){var n=t.item(i)
n&&e.push(n)}return e}
if("function"==typeof c.TouchEvent)return e=new c.TouchEvent(t.type,{touches:e(t.touches),targetTouches:e(t.targetTouches),changedTouches:e(t.changedTouches),ctrlKey:t.ctrlKey,shiftKey:t.shiftKey,altKey:t.altKey,metaKey:t.metaKey,bubbles:t.bubbles,cancelable:t.cancelable,composed:t.composed,detail:t.detail,view:t.view}),t.defaultPrevented&&e.preventDefault(),e;(e=this.cloneMouseEvent(t)).touches=t.touches
e.changedTouches=t.changedTouches
e.targetTouches=t.targetTouches
return e},destroyBase:function(){u(this.chart.a11yProxyContainer)
this.domElementProvider.destroyCreatedElements()
this.eventProvider.removeAddedEvents()}}
t(s.prototype,{init:function(){},getKeyboardNavigation:function(){},onChartUpdate:function(){},onChartRender:function(){},destroy:function(){}})
return s}))
e(t,"Accessibility/KeyboardNavigation.js",[t["Core/Globals.js"],t["Core/Utilities.js"],t["Accessibility/Utils/HTMLUtilities.js"],t["Accessibility/Utils/EventProvider.js"]],(function(t,e,i,n){function o(t,e){this.init(t,e)}var r=t.doc,s=t.win,a=e.addEvent,l=e.fireEvent,c=i.getElement
a(r,"keydown",(function(e){27===(e.which||e.keyCode)&&t.charts&&t.charts.forEach((function(t){t&&t.dismissPopupContent&&t.dismissPopupContent()}))}))
t.Chart.prototype.dismissPopupContent=function(){var t=this
l(this,"dismissPopupContent",{},(function(){t.tooltip&&t.tooltip.hide(0)
t.hideExportMenu()}))}
o.prototype={init:function(t,e){var i=this,o=this.eventProvider=new n
this.chart=t
this.components=e
this.modules=[]
this.currentModuleIx=0
this.update()
o.addEvent(this.tabindexContainer,"keydown",(function(t){return i.onKeydown(t)}))
o.addEvent(this.tabindexContainer,"focus",(function(t){return i.onFocus(t)}));["mouseup","touchend"].forEach((function(t){return o.addEvent(r,t,(function(){return i.onMouseUp()}))}));["mousedown","touchstart"].forEach((function(e){return o.addEvent(t.renderTo,e,(function(){i.isClickingChart=!0}))}))
o.addEvent(t.renderTo,"mouseover",(function(){i.pointerIsOverChart=!0}))
o.addEvent(t.renderTo,"mouseout",(function(){i.pointerIsOverChart=!1}))
this.modules.length&&this.modules[0].init(1)},update:function(t){var e=this.chart.options.accessibility
e=e&&e.keyboardNavigation
var i=this.components
this.updateContainerTabindex()
e&&e.enabled&&t&&t.length?(this.modules=t.reduce((function(t,e){e=i[e].getKeyboardNavigation()
return t.concat(e)}),[]),this.updateExitAnchor()):(this.modules=[],this.currentModuleIx=0,this.removeExitAnchor())},onFocus:function(t){var e,i=this.chart
t=t.relatedTarget&&i.container.contains(t.relatedTarget)
this.isClickingChart||t||null===(e=this.modules[0])||void 0===e||e.init(1)},onMouseUp:function(){delete this.isClickingChart
if(!this.keyboardReset&&!this.pointerIsOverChart){var t=this.chart,e=this.modules&&this.modules[this.currentModuleIx||0]
e&&e.terminate&&e.terminate()
t.focusElement&&t.focusElement.removeFocusBorder()
this.currentModuleIx=0
this.keyboardReset=!0}},onKeydown:function(t){t=t||s.event
var e,i=this.modules&&this.modules.length&&this.modules[this.currentModuleIx]
this.keyboardReset=!1
if(i){var n=i.run(t)
n===i.response.success?e=!0:n===i.response.prev?e=this.prev():n===i.response.next&&(e=this.next())
e&&(t.preventDefault(),t.stopPropagation())}},prev:function(){return this.move(-1)},next:function(){return this.move(1)},move:function(t){var e=this.modules&&this.modules[this.currentModuleIx]
e&&e.terminate&&e.terminate(t)
this.chart.focusElement&&this.chart.focusElement.removeFocusBorder()
this.currentModuleIx+=t
if(e=this.modules&&this.modules[this.currentModuleIx]){if(e.validate&&!e.validate())return this.move(t)
if(e.init)return e.init(t),!0}this.currentModuleIx=0
0<t?(this.exiting=!0,this.exitAnchor.focus()):this.tabindexContainer.focus()
return!1},updateExitAnchor:function(){var t=c("highcharts-end-of-chart-marker-"+this.chart.index)
this.removeExitAnchor()
t?(this.makeElementAnExitAnchor(t),this.exitAnchor=t):this.createExitAnchor()},updateContainerTabindex:function(){var t=this.chart.options.accessibility
t=!((t=t&&t.keyboardNavigation)&&!1===t.enabled)
var e=this.chart,i=e.container
e.renderTo.hasAttribute("tabindex")&&(i.removeAttribute("tabindex"),i=e.renderTo)
this.tabindexContainer=i
var n=i.getAttribute("tabindex")
t&&!n?i.setAttribute("tabindex","0"):t||e.container.removeAttribute("tabindex")},makeElementAnExitAnchor:function(t){var e=this.tabindexContainer.getAttribute("tabindex")||0
t.setAttribute("class","highcharts-exit-anchor")
t.setAttribute("tabindex",e)
t.setAttribute("aria-hidden",!1)
this.addExitAnchorEventsToEl(t)},createExitAnchor:function(){var t=this.chart,e=this.exitAnchor=r.createElement("div")
t.renderTo.appendChild(e)
this.makeElementAnExitAnchor(e)},removeExitAnchor:function(){this.exitAnchor&&this.exitAnchor.parentNode&&(this.exitAnchor.parentNode.removeChild(this.exitAnchor),delete this.exitAnchor)},addExitAnchorEventsToEl:function(t){var e=this.chart,i=this
this.eventProvider.addEvent(t,"focus",(function(t){(t=t||s.event).relatedTarget&&e.container.contains(t.relatedTarget)||i.exiting?i.exiting=!1:(i.tabindexContainer.focus(),t.preventDefault(),i.modules&&i.modules.length&&(i.currentModuleIx=i.modules.length-1,(t=i.modules[i.currentModuleIx])&&t.validate&&!t.validate()?i.prev():t&&t.init(-1)))}))},destroy:function(){this.removeExitAnchor()
this.eventProvider.removeAddedEvents()
this.chart.container.removeAttribute("tabindex")}}
return o}))
e(t,"Accessibility/Components/LegendComponent.js",[t["Core/Globals.js"],t["Core/Legend.js"],t["Core/Utilities.js"],t["Accessibility/AccessibilityComponent.js"],t["Accessibility/KeyboardNavigationHandler.js"],t["Accessibility/Utils/HTMLUtilities.js"]],(function(t,e,i,n,o,r){function s(t){var e=t.legend&&t.legend.allItems,i=t.options.legend.accessibility||{}
return!(!e||!e.length||t.colorAxis&&t.colorAxis.length||!1===i.enabled)}var a=i.addEvent,l=i.extend,c=i.find,u=i.fireEvent,h=r.removeElement,d=r.stripHTMLTagsFromString
t.Chart.prototype.highlightLegendItem=function(t){var e=this.legend.allItems,i=this.highlightedLegendItemIx
if(e[t]){e[i]&&u(e[i].legendGroup.element,"mouseout")
var n=(i=this.legend).allItems[t].pageIx,o=i.currentPage
void 0!==n&&n+1!==o&&i.scroll(1+n-o)
this.setFocusToElement(e[t].legendItem,e[t].a11yProxyElement)
u(e[t].legendGroup.element,"mouseover")
return!0}return!1}
a(e,"afterColorizeItem",(function(t){var e=t.item
this.chart.options.accessibility.enabled&&e&&e.a11yProxyElement&&e.a11yProxyElement.setAttribute("aria-pressed",t.visible?"true":"false")}));(t=function(){}).prototype=new n
l(t.prototype,{init:function(){var t=this
this.proxyElementsList=[]
this.recreateProxies()
this.addEvent(e,"afterScroll",(function(){this.chart===t.chart&&(t.updateProxiesPositions(),t.updateLegendItemProxyVisibility(),this.chart.highlightLegendItem(t.highlightedLegendItemIx))}))
this.addEvent(e,"afterPositionItem",(function(e){this.chart===t.chart&&this.chart.renderer&&t.updateProxyPositionForItem(e.item)}))},updateLegendItemProxyVisibility:function(){var t=this.chart.legend,e=t.currentPage||1,i=t.clipHeight||0;(t.allItems||[]).forEach((function(n){var o=n.pageIx||0
o=(n._legendItemPos?n._legendItemPos[1]:0)+(n.legendItem?Math.round(n.legendItem.getBBox().height):0)-t.pages[o]>i||o!==e-1
n.a11yProxyElement&&(n.a11yProxyElement.style.visibility=o?"hidden":"visible")}))},onChartRender:function(){s(this.chart)?this.updateProxiesPositions():this.removeProxies()},onChartUpdate:function(){this.updateLegendTitle()},updateProxiesPositions:function(){for(var t=0,e=this.proxyElementsList;t<e.length;t++){var i=e[t]
this.updateProxyButtonPosition(i.element,i.posElement)}},updateProxyPositionForItem:function(t){var e=c(this.proxyElementsList,(function(e){return e.item===t}))
e&&this.updateProxyButtonPosition(e.element,e.posElement)},recreateProxies:function(){this.removeProxies()
s(this.chart)&&(this.addLegendProxyGroup(),this.proxyLegendItems(),this.updateLegendItemProxyVisibility())},removeProxies:function(){h(this.legendProxyGroup)
this.proxyElementsList=[]},updateLegendTitle:function(){var t,e,i=this.chart,n=d(((null===(e=null===(t=i.legend)||void 0===t?void 0:t.options.title)||void 0===e?void 0:e.text)||"").replace(/<br ?\/?>/g," "))
t=i.langFormat("accessibility.legend.legendLabel"+(n?"":"NoTitle"),{chart:i,legendTitle:n})
this.legendProxyGroup&&this.legendProxyGroup.setAttribute("aria-label",t)},addLegendProxyGroup:function(){this.legendProxyGroup=this.addProxyGroup({"aria-label":"_placeholder_",role:"all"===this.chart.options.accessibility.landmarkVerbosity?"region":null})},proxyLegendItems:function(){var t=this;(this.chart.legend&&this.chart.legend.allItems||[]).forEach((function(e){e.legendItem&&e.legendItem.element&&t.proxyLegendItem(e)}))},proxyLegendItem:function(t){if(t.legendItem&&t.legendGroup){var e=this.chart.langFormat("accessibility.legend.legendItem",{chart:this.chart,itemName:d(t.name)}),i=t.legendGroup.div?t.legendItem:t.legendGroup
t.a11yProxyElement=this.createProxyButton(t.legendItem,this.legendProxyGroup,{tabindex:-1,"aria-pressed":t.visible,"aria-label":e},i)
this.proxyElementsList.push({item:t,element:t.a11yProxyElement,posElement:i})}},getKeyboardNavigation:function(){var t=this.keyCodes,e=this
return new o(this.chart,{keyCodeMap:[[[t.left,t.right,t.up,t.down],function(t){return e.onKbdArrowKey(this,t)}],[[t.enter,t.space],function(){return e.onKbdClick(this)}]],validate:function(){return e.shouldHaveLegendNavigation()},init:function(t){return e.onKbdNavigationInit(t)}})},onKbdArrowKey:function(t,e){var i=this.keyCodes,n=t.response,o=this.chart,r=o.options.accessibility,s=o.legend.allItems.length
e=e===i.left||e===i.up?-1:1
return o.highlightLegendItem(this.highlightedLegendItemIx+e)?(this.highlightedLegendItemIx+=e,n.success):1<s&&r.keyboardNavigation.wrapAround?(t.init(e),n.success):n[0<e?"next":"prev"]},onKbdClick:function(t){var e=this.chart.legend.allItems[this.highlightedLegendItemIx]
e&&e.a11yProxyElement&&u(e.a11yProxyElement,"click")
return t.response.success},shouldHaveLegendNavigation:function(){var t=this.chart,e=t.colorAxis&&t.colorAxis.length,i=(t.options.legend||{}).accessibility||{}
return!!(t.legend&&t.legend.allItems&&t.legend.display&&!e&&i.enabled&&i.keyboardNavigation&&i.keyboardNavigation.enabled)},onKbdNavigationInit:function(t){var e=this.chart,i=e.legend.allItems.length-1
t=0<t?0:i
e.highlightLegendItem(t)
this.highlightedLegendItemIx=t}})
return t}))
e(t,"Accessibility/Components/MenuComponent.js",[t["Core/Globals.js"],t["Core/Utilities.js"],t["Accessibility/AccessibilityComponent.js"],t["Accessibility/KeyboardNavigationHandler.js"],t["Accessibility/Utils/ChartUtilities.js"],t["Accessibility/Utils/HTMLUtilities.js"]],(function(t,e,i,n,o,r){function s(t){return t.exportSVGElements&&t.exportSVGElements[0]}e=e.extend
var a=o.unhideChartElementFromAT,l=r.removeElement,c=r.getFakeMouseEvent
t.Chart.prototype.showExportMenu=function(){var t=s(this)
t&&(t=t.element).onclick&&t.onclick(c("click"))}
t.Chart.prototype.hideExportMenu=function(){var t=this.exportDivElements
t&&this.exportContextMenu&&(t.forEach((function(t){"highcharts-menu-item"===t.className&&t.onmouseout&&t.onmouseout(c("mouseout"))})),this.highlightedExportItemIx=0,this.exportContextMenu.hideMenu(),this.container.focus())}
t.Chart.prototype.highlightExportItem=function(t){var e=this.exportDivElements&&this.exportDivElements[t],i=this.exportDivElements&&this.exportDivElements[this.highlightedExportItemIx]
if(e&&"LI"===e.tagName&&(!e.children||!e.children.length)){var n=!!(this.renderTo.getElementsByTagName("g")[0]||{}).focus
e.focus&&n&&e.focus()
i&&i.onmouseout&&i.onmouseout(c("mouseout"))
e.onmouseover&&e.onmouseover(c("mouseover"))
this.highlightedExportItemIx=t
return!0}return!1}
t.Chart.prototype.highlightLastExportItem=function(){var t
if(this.exportDivElements)for(t=this.exportDivElements.length;t--;)if(this.highlightExportItem(t))return!0
return!1};(t=function(){}).prototype=new i
e(t.prototype,{init:function(){var t=this.chart,e=this
this.addEvent(t,"exportMenuShown",(function(){e.onMenuShown()}))
this.addEvent(t,"exportMenuHidden",(function(){e.onMenuHidden()}))},onMenuHidden:function(){var t=this.chart.exportContextMenu
t&&t.setAttribute("aria-hidden","true")
this.isExportMenuShown=!1
this.setExportButtonExpandedState("false")},onMenuShown:function(){var t=this.chart,e=t.exportContextMenu
e&&(this.addAccessibleContextMenuAttribs(),a(t,e))
this.isExportMenuShown=!0
this.setExportButtonExpandedState("true")},setExportButtonExpandedState:function(t){var e=this.exportButtonProxy
e&&e.setAttribute("aria-expanded",t)},onChartRender:function(){var t=this.chart,e=t.options.accessibility
l(this.exportProxyGroup)
var i=t.options.exporting,n=s(t)
i&&!1!==i.enabled&&i.accessibility&&i.accessibility.enabled&&n&&n.element&&(this.exportProxyGroup=this.addProxyGroup("all"===e.landmarkVerbosity?{"aria-label":t.langFormat("accessibility.exporting.exportRegionLabel",{chart:t}),role:"region"}:{}),e=s(this.chart),this.exportButtonProxy=this.createProxyButton(e,this.exportProxyGroup,{"aria-label":t.langFormat("accessibility.exporting.menuButtonLabel",{chart:t}),"aria-expanded":"false"}))},addAccessibleContextMenuAttribs:function(){var t=this.chart,e=t.exportDivElements
e&&e.length&&(e.forEach((function(t){"LI"!==t.tagName||t.children&&t.children.length?t.setAttribute("aria-hidden","true"):t.setAttribute("tabindex",-1)})),(e=e[0].parentNode).removeAttribute("aria-hidden"),e.setAttribute("aria-label",t.langFormat("accessibility.exporting.chartMenuLabel",{chart:t})))},getKeyboardNavigation:function(){var t=this.keyCodes,e=this.chart,i=this
return new n(e,{keyCodeMap:[[[t.left,t.up],function(){return i.onKbdPrevious(this)}],[[t.right,t.down],function(){return i.onKbdNext(this)}],[[t.enter,t.space],function(){return i.onKbdClick(this)}]],validate:function(){return e.exportChart&&!1!==e.options.exporting.enabled&&!1!==e.options.exporting.accessibility.enabled},init:function(){var t=i.exportButtonProxy,n=e.exportingGroup
n&&t&&e.setFocusToElement(n,t)},terminate:function(){e.hideExportMenu()}})},onKbdPrevious:function(t){var e=this.chart,i=e.options.accessibility
t=t.response
for(var n=e.highlightedExportItemIx||0;n--;)if(e.highlightExportItem(n))return t.success
return i.keyboardNavigation.wrapAround?(e.highlightLastExportItem(),t.success):t.prev},onKbdNext:function(t){var e=this.chart,i=e.options.accessibility
t=t.response
for(var n=(e.highlightedExportItemIx||0)+1;n<e.exportDivElements.length;++n)if(e.highlightExportItem(n))return t.success
return i.keyboardNavigation.wrapAround?(e.highlightExportItem(0),t.success):t.next},onKbdClick:function(t){var e=this.chart,i=e.exportDivElements[e.highlightedExportItemIx],n=s(e).element
this.isExportMenuShown?this.fakeClickEvent(i):(this.fakeClickEvent(n),e.highlightExportItem(0))
return t.response.success}})
return t}))
e(t,"Accessibility/Components/SeriesComponent/SeriesKeyboardNavigation.js",[t["Core/Chart/Chart.js"],t["Core/Series/Point.js"],t["Core/Series/Series.js"],t["Core/Series/SeriesRegistry.js"],t["Core/Utilities.js"],t["Accessibility/KeyboardNavigationHandler.js"],t["Accessibility/Utils/EventProvider.js"],t["Accessibility/Utils/ChartUtilities.js"]],(function(t,e,i,n,o,r,s,a){function l(t){var e=t.index,i=t.series.points,n=i.length
if(i[e]===t)return e
for(;n--;)if(i[n]===t)return n}function c(t){var e=t.chart.options.accessibility.keyboardNavigation.seriesNavigation,i=t.options.accessibility||{},n=i.keyboardNavigation
return n&&!1===n.enabled||!1===i.enabled||!1===t.options.enableMouseTracking||!t.visible||e.pointNavigationEnabledThreshold&&e.pointNavigationEnabledThreshold<=t.points.length}function u(t){var e,i=t.series.chart.options.accessibility,n=!1===(null===(e=t.options.accessibility)||void 0===e?void 0:e.enabled)
return t.isNull&&i.keyboardNavigation.seriesNavigation.skipNullPoints||!1===t.visible||!1===t.isInside||n||c(t.series)}function h(t){delete t.highlightedPoint
return t.series.reduce((function(t,e){return t||e.highlightFirstValidPoint()}),!1)}function d(t,e){this.keyCodes=e
this.chart=t}var p=n.seriesTypes,m=o.defined,g=o.extend,f=o.fireEvent,b=a.getPointFromXY,y=a.getSeriesFromName,v=a.scrollToPoint
i.prototype.keyboardMoveVertical=!0;["column","pie"].forEach((function(t){p[t]&&(p[t].prototype.keyboardMoveVertical=!1)}))
e.prototype.highlight=function(){var t=this.series.chart
this.isNull?t.tooltip&&t.tooltip.hide(0):this.onMouseOver()
v(this)
this.graphic&&t.setFocusToElement(this.graphic)
t.highlightedPoint=this
return this}
t.prototype.highlightAdjacentPoint=function(t){var e=this.series,i=this.highlightedPoint,n=i&&l(i)||0,o=i&&i.series.points,r=this.series&&this.series[this.series.length-1]
r=r&&r.points&&r.points[r.points.length-1]
if(!e[0]||!e[0].points)return!1
if(i){if(e=e[i.series.index+(t?1:-1)],!(n=o[n+(t?1:-1)])&&e&&(n=e.points[t?0:e.points.length-1]),!n)return!1}else n=t?e[0].points[0]:r
return u(n)?(c(e=n.series)?this.highlightedPoint=t?e.points[e.points.length-1]:e.points[0]:this.highlightedPoint=n,this.highlightAdjacentPoint(t)):n.highlight()}
i.prototype.highlightFirstValidPoint=function(){var t=this.chart.highlightedPoint,e=(t&&t.series)===this?l(t):0,i=(t=this.points).length
if(t&&i){for(var n=e;n<i;++n)if(!u(t[n]))return t[n].highlight()
for(;0<=e;--e)if(!u(t[e]))return t[e].highlight()}return!1}
t.prototype.highlightAdjacentSeries=function(t){var e,i=this.highlightedPoint,n=(e=this.series&&this.series[this.series.length-1])&&e.points&&e.points[e.points.length-1]
if(!this.highlightedPoint)return e=t?this.series&&this.series[0]:e,!!(n=t?e&&e.points&&e.points[0]:n)&&n.highlight()
if(!(e=this.series[i.series.index+(t?-1:1)]))return!1
n=function(t,e,i,n){var o=1/0,r=e.points.length,s=function(t){return!(m(t.plotX)&&m(t.plotY))}
if(!s(t)){for(;r--;){var a=e.points[r]
if(!s(a)&&(a=(t.plotX-a.plotX)*(t.plotX-a.plotX)*(i||1)+(t.plotY-a.plotY)*(t.plotY-a.plotY)*(n||1))<o){o=a
var l=r}}return m(l)?e.points[l]:void 0}}(i,e,4)
if(!n)return!1
if(c(e))return n.highlight(),(t=this.highlightAdjacentSeries(t))||(i.highlight(),!1)
n.highlight()
return n.series.highlightFirstValidPoint()}
t.prototype.highlightAdjacentPointVertical=function(t){var e,i=this.highlightedPoint,n=1/0
if(!m(i.plotX)||!m(i.plotY))return!1
this.series.forEach((function(o){c(o)||o.points.forEach((function(r){if(m(r.plotY)&&m(r.plotX)&&r!==i){var s=r.plotY-i.plotY,a=Math.abs(r.plotX-i.plotX)
a=Math.abs(s)*Math.abs(s)+a*a*4
o.yAxis&&o.yAxis.reversed&&(s*=-1)
!(0>=s&&t||0<=s&&!t||5>a||u(r))&&a<n&&(n=a,e=r)}}))}))
return!!e&&e.highlight()}
g(d.prototype,{init:function(){var t=this,e=this.chart,n=this.eventProvider=new s
n.addEvent(i,"destroy",(function(){return t.onSeriesDestroy(this)}))
n.addEvent(e,"afterDrilldown",(function(){h(this)
this.focusElement&&this.focusElement.removeFocusBorder()}))
n.addEvent(e,"drilldown",(function(e){var i=(e=e.point).series
t.lastDrilledDownPoint={x:e.x,y:e.y,seriesName:i?i.name:""}}))
n.addEvent(e,"drillupall",(function(){setTimeout((function(){t.onDrillupAll()}),10)}))},onDrillupAll:function(){var t,e=this.lastDrilledDownPoint,i=this.chart,n=e&&y(i,e.seriesName)
e&&n&&m(e.x)&&m(e.y)&&(t=b(n,e.x,e.y))
i.container&&i.container.focus()
t&&t.highlight&&t.highlight()
i.focusElement&&i.focusElement.removeFocusBorder()},getKeyboardNavigationHandler:function(){var t=this,e=this.keyCodes,i=this.chart,n=i.inverted
return new r(i,{keyCodeMap:[[n?[e.up,e.down]:[e.left,e.right],function(e){return t.onKbdSideways(this,e)}],[n?[e.left,e.right]:[e.up,e.down],function(e){return t.onKbdVertical(this,e)}],[[e.enter,e.space],function(t,e){(t=i.highlightedPoint)&&(f(t.series,"click",g(e,{point:t})),t.firePointEvent("click"))
return this.response.success}]],init:function(e){return t.onHandlerInit(this,e)},terminate:function(){return t.onHandlerTerminate()}})},onKbdSideways:function(t,e){var i=this.keyCodes
return this.attemptHighlightAdjacentPoint(t,e===i.right||e===i.down)},onKbdVertical:function(t,e){var i=this.chart,n=this.keyCodes
e=e===n.down||e===n.right
if((n=i.options.accessibility.keyboardNavigation.seriesNavigation).mode&&"serialize"===n.mode)return this.attemptHighlightAdjacentPoint(t,e)
i[i.highlightedPoint&&i.highlightedPoint.series.keyboardMoveVertical?"highlightAdjacentPointVertical":"highlightAdjacentSeries"](e)
return t.response.success},onHandlerInit:function(t,e){var i=this.chart
if(0<e)h(i)
else{e=i.series.length
for(;e--&&!(i.highlightedPoint=i.series[e].points[i.series[e].points.length-1],i.series[e].highlightFirstValidPoint()););}return t.response.success},onHandlerTerminate:function(){var t,e,i=this.chart,n=i.highlightedPoint
null===(t=i.tooltip)||void 0===t||t.hide(0)
null===(e=null==n?void 0:n.onMouseOut)||void 0===e||e.call(n)
delete i.highlightedPoint},attemptHighlightAdjacentPoint:function(t,e){var i=this.chart,n=i.options.accessibility.keyboardNavigation.wrapAround
return i.highlightAdjacentPoint(e)?t.response.success:n?t.init(e?1:-1):t.response[e?"next":"prev"]},onSeriesDestroy:function(t){var e=this.chart
e.highlightedPoint&&e.highlightedPoint.series===t&&(delete e.highlightedPoint,e.focusElement&&e.focusElement.removeFocusBorder())},destroy:function(){this.eventProvider.removeAddedEvents()}})
return d}))
e(t,"Accessibility/Components/AnnotationsA11y.js",[t["Accessibility/Utils/HTMLUtilities.js"]],(function(t){function e(t){return(t.annotations||[]).reduce((function(t,e){var i
!1!==(null===(i=e.options)||void 0===i?void 0:i.visible)&&(t=t.concat(e.labels))
return t}),[])}function i(t){var e,i,n,o,r=null===(i=null===(e=t.options)||void 0===e?void 0:e.accessibility)||void 0===i?void 0:i.description
return r||((null===(o=null===(n=t.graphic)||void 0===n?void 0:n.text)||void 0===o?void 0:o.textStr)||"")}function n(t){var e,n,o=null===(n=null===(e=t.options)||void 0===e?void 0:e.accessibility)||void 0===n?void 0:n.description
if(o)return o
e=t.chart
o=i(t)
var r=t.points.filter((function(t){return!!t.graphic})).map((function(t){var e,i
if(!(i=null===(e=null==t?void 0:t.accessibility)||void 0===e?void 0:e.valueDescription)){var n,o
i=(null===(o=null===(n=null==t?void 0:t.graphic)||void 0===n?void 0:n.element)||void 0===o?void 0:o.getAttribute("aria-label"))||""}return((t=(null==t?void 0:t.series.name)||"")?t+", ":"")+"data point "+i})).filter((function(t){return!!t})),s=r.length
n="accessibility.screenReaderSection.annotations.description"+(1<s?"MultiplePoints":s?"SinglePoint":"NoPoints")
t={annotationText:o,annotation:t,numPoints:s,annotationPoint:r[0],additionalAnnotationPoints:r.slice(1)}
return e.langFormat(n,t)}function o(t){return e(t).map((function(t){return(t=r(s(n(t))))?"<li>"+t+"</li>":""}))}var r=t.escapeStringForHTML,s=t.stripHTMLTagsFromString
return{getAnnotationsInfoHTML:function(t){var e=t.annotations
return e&&e.length?'<ul style="list-style-type: none">'+o(t).join(" ")+"</ul>":""},getAnnotationLabelDescription:n,getAnnotationListItems:o,getPointAnnotationTexts:function(t){var n=e(t.series.chart).filter((function(e){return-1<e.points.indexOf(t)}))
return n.length?n.map((function(t){return""+i(t)})):[]}}}))
e(t,"Accessibility/Components/SeriesComponent/SeriesDescriber.js",[t["Accessibility/Components/AnnotationsA11y.js"],t["Accessibility/Utils/ChartUtilities.js"],t["Accessibility/Utils/HTMLUtilities.js"],t["Core/Tooltip.js"],t["Core/Utilities.js"]],(function(t,e,i,n,o){function r(t){var e=t.chart.options.accessibility.series.pointDescriptionEnabledThreshold
return!!(!1!==e&&t.points&&t.points.length>=e)}function s(t,e){var i=t.series.chart,n=i.options.accessibility.point||{}
t=t.series.tooltipOptions||{}
i=i.options.lang
return T(e)?E(e,n.valueDecimals||t.valueDecimals||-1,i.decimalPoint,i.accessibility.thousandsSep||i.thousandsSep):e}function a(t,e){return t.chart.langFormat("accessibility.series."+e+"Description",{name:f(t[e]),series:t})}function l(t){var e=t.series,i=e.chart,o=i.options.accessibility.point||{}
if(e.xAxis&&e.xAxis.dateTime)return e=n.prototype.getXDateFormat.call({getDateFormat:n.prototype.getDateFormat,chart:i},t,i.options.tooltip,e.xAxis),o=o.dateFormatter&&o.dateFormatter(t)||o.dateFormat||e,i.time.dateFormat(o,t.x,void 0)}function c(t){var e=l(t),i=(t.series.xAxis||{}).categories&&P(t.category)&&(""+t.category).replace("<br/>"," "),n=t.id&&0>t.id.indexOf("highcharts-"),o="x, "+t.x
return t.name||e||i||(n?t.id:o)}function u(t){var e=t.series,i=e.chart.options.accessibility.point||{},n=e.tooltipOptions||{},o=i.valuePrefix||n.valuePrefix||""
i=i.valueSuffix||n.valueSuffix||""
n=s(t,t[void 0!==t.value?"value":"y"])
return t.isNull?e.chart.langFormat("accessibility.series.nullPointValue",{point:t}):e.pointArrayMap?function(t,e,i){var n=e||"",o=i||""
return t.series.pointArrayMap.reduce((function(e,i){e+=e.length?", ":""
var r=s(t,S(t[i],t.options[i]))
return e+(i+": ")+n+r+o}),"")}(t,o,i):o+n+i}function h(t){var e=t.series,i=e.chart,n=i.options.accessibility.point.valueDescriptionFormat,o=(e=S(e.xAxis&&e.xAxis.options.accessibility&&e.xAxis.options.accessibility.enabled,!i.angular))?c(t):""
t={point:t,index:P(t.index)?t.index+1:"",xDescription:o,value:u(t),separator:e?", ":""}
return C(n,t,i)}function d(t){var e=t.series,i=e.chart,n=h(t),o=t.options&&t.options.accessibility&&t.options.accessibility.description
o=o?" "+o:""
e=1<i.series.length&&e.name?" "+e.name+".":""
i=t.series.chart
var r=g(t),s={point:t,annotations:r}
i=r.length?i.langFormat("accessibility.series.pointAnnotationsDescription",s):""
t.accessibility=t.accessibility||{}
t.accessibility.valueDescription=n
return n+o+e+(i?" "+i:"")}function p(t){var e=function(t){var e=t.options.accessibility||{}
return!r(t)&&!e.exposeAsGroupOnly}(t),i=function(t){var e=t.chart.options.accessibility.keyboardNavigation.seriesNavigation
return!(!t.points||!(t.points.length<e.pointNavigationEnabledThreshold||!1===e.pointNavigationEnabledThreshold))}(t);(e||i)&&t.points.forEach((function(t){var i,n,o
if(!(o=t.graphic&&t.graphic.element)&&(o=t.series&&t.series.is("sunburst"),o=t.isNull&&!o)){var r=t.series,s=function(t){var e=t.index
return t.series&&t.series.data&&P(e)&&w(t.series.data,(function(t){return!!(t&&void 0!==t.index&&t.index>e&&t.graphic&&t.graphic.element)}))||null}(t)
r=(o=s&&s.graphic)?o.parentGroup:r.graph||r.group
s=s?{x:S(t.plotX,s.plotX,0),y:S(t.plotY,s.plotY,0)}:{x:S(t.plotX,0),y:S(t.plotY,0)};(s=t.series.chart.renderer.rect(s.x,s.y,1,1)).attr({class:"highcharts-a11y-dummy-point",fill:"none",opacity:0,"fill-opacity":0,"stroke-opacity":0})
r&&r.element?(t.graphic=s,t.hasDummyGraphic=!0,s.add(r),r.element.insertBefore(s.element,o?o.element:null),o=s.element):o=void 0}r=!1===(null===(n=null===(i=t.options)||void 0===i?void 0:i.accessibility)||void 0===n?void 0:n.enabled)
o&&(o.setAttribute("tabindex","-1"),o.style.outline="0",e&&!r?(i=(n=t.series).chart.options.accessibility.point||{},n=n.options.accessibility||{},t=A(n.pointDescriptionFormatter&&n.pointDescriptionFormatter(t)||i.descriptionFormatter&&i.descriptionFormatter(t)||d(t)),o.setAttribute("role","img"),o.setAttribute("aria-label",t)):o.setAttribute("aria-hidden",!0))}))}function m(t){var e=t.chart,i=e.types||[],n=function(t){var e=(t.options.accessibility||{}).description
return e&&t.chart.langFormat("accessibility.series.description",{description:e,series:t})||""}(t),o=function(i){return e[i]&&1<e[i].length&&t[i]},r=a(t,"xAxis"),s=a(t,"yAxis"),l={name:t.name||"",ix:t.index+1,numSeries:e.series&&e.series.length,numPoints:t.points&&t.points.length,series:t}
i=1<i.length?"Combination":""
return(e.langFormat("accessibility.series.summary."+t.type+i,l)||e.langFormat("accessibility.series.summary.default"+i,l))+(n?" "+n:"")+(o("yAxis")?" "+s:"")+(o("xAxis")?" "+r:"")}var g=t.getPointAnnotationTexts,f=e.getAxisDescription,b=e.getSeriesFirstPointElement,y=e.getSeriesA11yElement,v=e.unhideChartElementFromAT,x=i.reverseChildNodes,A=i.stripHTMLTagsFromString,w=o.find,C=o.format,T=o.isNumber,E=o.numberFormat,S=o.pick,P=o.defined
return{describeSeries:function(t){var e=t.chart,i=b(t),n=y(t),o=e.is3d&&e.is3d()
if(n){n.lastChild!==i||o||x(n)
p(t)
v(e,n)
e=(o=t.chart).options.chart||{}
i=1<o.series.length
o=o.options.accessibility.series.describeSingleSeries
var s=(t.options.accessibility||{}).exposeAsGroupOnly
e.options3d&&e.options3d.enabled&&i||!(i||o||s||r(t))?n.setAttribute("aria-label",""):(i=(e=t.chart.options.accessibility).landmarkVerbosity,(t.options.accessibility||{}).exposeAsGroupOnly?n.setAttribute("role","img"):"all"===i&&n.setAttribute("role","region"),n.setAttribute("tabindex","-1"),n.style.outline="0",n.setAttribute("aria-label",A(e.series.descriptionFormatter&&e.series.descriptionFormatter(t)||m(t))))}},defaultPointDescriptionFormatter:d,defaultSeriesDescriptionFormatter:m,getPointA11yTimeDescription:l,getPointXDescription:c,getPointValue:u,getPointValueDescription:h}}))
e(t,"Accessibility/Utils/Announcer.js",[t["Core/Globals.js"],t["Core/Renderer/HTML/AST.js"],t["Accessibility/Utils/DOMElementProvider.js"],t["Accessibility/Utils/HTMLUtilities.js"]],(function(t,e,i,n){var o=t.doc,r=n.setElAttrs,s=n.visuallyHideElement
n=function(){function t(t,e){this.chart=t
this.domElementProvider=new i
this.announceRegion=this.addAnnounceRegion(e)}t.prototype.destroy=function(){this.domElementProvider.destroyCreatedElements()}
t.prototype.announce=function(t){var i=this
e.setElementHTML(this.announceRegion,t)
this.clearAnnouncementRegionTimer&&clearTimeout(this.clearAnnouncementRegionTimer)
this.clearAnnouncementRegionTimer=setTimeout((function(){i.announceRegion.innerHTML=""
delete i.clearAnnouncementRegionTimer}),1e3)}
t.prototype.addAnnounceRegion=function(t){var e=this.chart.announcerContainer||this.createAnnouncerContainer(),i=this.domElementProvider.createElement("div")
r(i,{"aria-hidden":!1,"aria-live":t})
s(i)
e.appendChild(i)
return i}
t.prototype.createAnnouncerContainer=function(){var t=this.chart,e=o.createElement("div")
r(e,{"aria-hidden":!1,style:"position:relative",class:"highcharts-announcer-container"})
t.renderTo.insertBefore(e,t.renderTo.firstChild)
return t.announcerContainer=e}
return t}()
return t.Announcer=n}))
e(t,"Accessibility/Components/SeriesComponent/NewDataAnnouncer.js",[t["Core/Globals.js"],t["Core/Series/Series.js"],t["Core/Utilities.js"],t["Accessibility/Utils/ChartUtilities.js"],t["Accessibility/Components/SeriesComponent/SeriesDescriber.js"],t["Accessibility/Utils/Announcer.js"],t["Accessibility/Utils/EventProvider.js"]],(function(t,e,i,n,o,r,s){var a=i.extend,l=i.defined,c=n.getChartTitle,u=o.defaultPointDescriptionFormatter,h=o.defaultSeriesDescriptionFormatter
i=function(t){this.chart=t}
a(i.prototype,{init:function(){var t=this.chart,e=t.options.accessibility.announceNewData.interruptUser?"assertive":"polite"
this.lastAnnouncementTime=0
this.dirty={allSeries:{}}
this.eventProvider=new s
this.announcer=new r(t,e)
this.addEventListeners()},destroy:function(){this.eventProvider.removeAddedEvents()
this.announcer.destroy()},addEventListeners:function(){var t=this,i=this.chart,n=this.eventProvider
n.addEvent(i,"afterDrilldown",(function(){t.lastAnnouncementTime=0}))
n.addEvent(e,"updatedData",(function(){t.onSeriesUpdatedData(this)}))
n.addEvent(i,"afterAddSeries",(function(e){t.onSeriesAdded(e.series)}))
n.addEvent(e,"addPoint",(function(e){t.onPointAdded(e.point)}))
n.addEvent(i,"redraw",(function(){t.announceDirtyData()}))},onSeriesUpdatedData:function(t){var e=this.chart
t.chart===e&&e.options.accessibility.announceNewData.enabled&&(this.dirty.hasDirty=!0,this.dirty.allSeries[t.name+t.index]=t)},onSeriesAdded:function(t){this.chart.options.accessibility.announceNewData.enabled&&(this.dirty.hasDirty=!0,this.dirty.allSeries[t.name+t.index]=t,this.dirty.newSeries=l(this.dirty.newSeries)?void 0:t)},onPointAdded:function(t){var e=t.series.chart
this.chart===e&&e.options.accessibility.announceNewData.enabled&&(this.dirty.newPoint=l(this.dirty.newPoint)?void 0:t)},announceDirtyData:function(){var t=this
if(this.chart.options.accessibility.announceNewData&&this.dirty.hasDirty){var e=this.dirty.newPoint
e&&(e=function(t){var e=t.series.data.filter((function(e){return t.x===e.x&&t.y===e.y}))
return 1===e.length?e[0]:t}(e))
this.queueAnnouncement(Object.keys(this.dirty.allSeries).map((function(e){return t.dirty.allSeries[e]})),this.dirty.newSeries,e)
this.dirty={allSeries:{}}}},queueAnnouncement:function(t,e,i){var n=this,o=this.chart.options.accessibility.announceNewData
if(o.enabled){var r=+new Date
o=Math.max(0,o.minAnnounceInterval-(r-this.lastAnnouncementTime))
t=function(t,e){var i=(t||[]).concat(e||[]).reduce((function(t,e){t[e.name+e.index]=e
return t}),{})
return Object.keys(i).map((function(t){return i[t]}))}(this.queuedAnnouncement&&this.queuedAnnouncement.series,t);(e=this.buildAnnouncementMessage(t,e,i))&&(this.queuedAnnouncement&&clearTimeout(this.queuedAnnouncementTimer),this.queuedAnnouncement={time:r,message:e,series:t},this.queuedAnnouncementTimer=setTimeout((function(){n&&n.announcer&&(n.lastAnnouncementTime=+new Date,n.announcer.announce(n.queuedAnnouncement.message),delete n.queuedAnnouncement,delete n.queuedAnnouncementTimer)}),o))}},buildAnnouncementMessage:function(e,i,n){var o=this.chart,r=o.options.accessibility.announceNewData
if(r.announcementFormatter&&!1!==(e=r.announcementFormatter(e,i,n)))return e.length?e:null
e=t.charts&&1<t.charts.length?"Multiple":"Single"
e=i?"newSeriesAnnounce"+e:n?"newPointAnnounce"+e:"newDataAnnounce"
r=c(o)
return o.langFormat("accessibility.announceNewData."+e,{chartTitle:r,seriesDesc:i?h(i):null,pointDesc:n?u(n):null,point:n,series:i})}})
return i}))
e(t,"Accessibility/Components/SeriesComponent/ForcedMarkers.js",[t["Core/Series/Series.js"],t["Core/Utilities.js"]],(function(t,e){function i(t){o(!0,t,{marker:{enabled:!0,states:{normal:{opacity:0}}}})}var n=e.addEvent,o=e.merge
return function(){n(t,"render",(function(){var t=this.options,e=!1!==(this.options.accessibility&&this.options.accessibility.enabled);(e=this.chart.options.accessibility.enabled&&e)&&(e=this.chart.options.accessibility,e=this.points.length<e.series.pointDescriptionEnabledThreshold||!1===e.series.pointDescriptionEnabledThreshold)
if(e){if(t.marker&&!1===t.marker.enabled&&(this.a11yMarkersForced=!0,i(this.options)),this._hasPointMarkers&&this.points&&this.points.length)for(t=this.points.length;t--;){var n=(e=this.points[t]).options
delete e.hasForcedA11yMarker
n.marker&&(n.marker.enabled?(o(!0,n.marker,{states:{normal:{opacity:n.marker.states&&n.marker.states.normal&&n.marker.states.normal.opacity||1}}}),e.hasForcedA11yMarker=!1):(i(n),e.hasForcedA11yMarker=!0))}}else this.a11yMarkersForced&&(delete this.a11yMarkersForced,(t=this.resetA11yMarkerOptions)&&o(!0,this.options,{marker:{enabled:t.enabled,states:{normal:{opacity:t.states&&t.states.normal&&t.states.normal.opacity}}}}))}))
n(t,"afterSetOptions",(function(t){this.resetA11yMarkerOptions=o(t.options.marker||{},this.userOptions.marker||{})}))
n(t,"afterRender",(function(){if(this.chart.styledMode){this.markerGroup&&this.markerGroup[this.a11yMarkersForced?"addClass":"removeClass"]("highcharts-a11y-markers-hidden")
this._hasPointMarkers&&this.points&&this.points.length&&this.points.forEach((function(t){t.graphic&&(t.graphic[t.hasForcedA11yMarker?"addClass":"removeClass"]("highcharts-a11y-marker-hidden"),t.graphic[!1===t.hasForcedA11yMarker?"addClass":"removeClass"]("highcharts-a11y-marker-visible"))}))}}))}}))
e(t,"Accessibility/Components/SeriesComponent/SeriesComponent.js",[t["Core/Globals.js"],t["Core/Utilities.js"],t["Accessibility/AccessibilityComponent.js"],t["Accessibility/Components/SeriesComponent/SeriesKeyboardNavigation.js"],t["Accessibility/Components/SeriesComponent/NewDataAnnouncer.js"],t["Accessibility/Components/SeriesComponent/ForcedMarkers.js"],t["Accessibility/Utils/ChartUtilities.js"],t["Accessibility/Components/SeriesComponent/SeriesDescriber.js"],t["Core/Tooltip.js"]],(function(t,e,i,n,o,r,s,a,l){e=e.extend
var c=s.hideSeriesFromAT,u=a.describeSeries
t.SeriesAccessibilityDescriber=a
r();(t=function(){}).prototype=new i
e(t.prototype,{init:function(){this.newDataAnnouncer=new o(this.chart)
this.newDataAnnouncer.init()
this.keyboardNavigation=new n(this.chart,this.keyCodes)
this.keyboardNavigation.init()
this.hideTooltipFromATWhenShown()
this.hideSeriesLabelsFromATWhenShown()},hideTooltipFromATWhenShown:function(){var t=this
this.addEvent(l,"refresh",(function(){this.chart===t.chart&&this.label&&this.label.element&&this.label.element.setAttribute("aria-hidden",!0)}))},hideSeriesLabelsFromATWhenShown:function(){this.addEvent(this.chart,"afterDrawSeriesLabels",(function(){this.series.forEach((function(t){t.labelBySeries&&t.labelBySeries.attr("aria-hidden",!0)}))}))},onChartRender:function(){this.chart.series.forEach((function(t){!1!==(t.options.accessibility&&t.options.accessibility.enabled)&&t.visible?u(t):c(t)}))},getKeyboardNavigation:function(){return this.keyboardNavigation.getKeyboardNavigationHandler()},destroy:function(){this.newDataAnnouncer.destroy()
this.keyboardNavigation.destroy()}})
return t}))
e(t,"Accessibility/Components/ZoomComponent.js",[t["Accessibility/AccessibilityComponent.js"],t["Accessibility/Utils/ChartUtilities.js"],t["Core/Globals.js"],t["Accessibility/Utils/HTMLUtilities.js"],t["Accessibility/KeyboardNavigationHandler.js"],t["Core/Utilities.js"]],(function(t,e,i,n,o,r){var s=e.unhideChartElementFromAT
e=i.noop
var a=n.removeElement,l=n.setElAttrs
n=r.extend
var c=r.pick
i.Axis.prototype.panStep=function(t,e){var i=e||3,n=((e=this.getExtremes()).max-e.min)/i*t,o=(i=e.max+n)-(n=e.min+n)
0>t&&n<e.dataMin?i=(n=e.dataMin)+o:0<t&&i>e.dataMax&&(n=(i=e.dataMax)-o)
this.setExtremes(n,i)}
e.prototype=new t
n(e.prototype,{init:function(){var t=this,e=this.chart;["afterShowResetZoom","afterDrilldown","drillupall"].forEach((function(i){t.addEvent(e,i,(function(){t.updateProxyOverlays()}))}))},onChartUpdate:function(){var t=this.chart,e=this
t.mapNavButtons&&t.mapNavButtons.forEach((function(i,n){s(t,i.element)
e.setMapNavButtonAttrs(i.element,"accessibility.zoom.mapZoom"+(n?"Out":"In"))}))},setMapNavButtonAttrs:function(t,e){var i=this.chart
e=i.langFormat(e,{chart:i})
l(t,{tabindex:-1,role:"button","aria-label":e})},onChartRender:function(){this.updateProxyOverlays()},updateProxyOverlays:function(){var t=this.chart
a(this.drillUpProxyGroup)
a(this.resetZoomProxyGroup)
t.resetZoomButton&&this.recreateProxyButtonAndGroup(t.resetZoomButton,"resetZoomProxyButton","resetZoomProxyGroup",t.langFormat("accessibility.zoom.resetZoomButton",{chart:t}))
t.drillUpButton&&this.recreateProxyButtonAndGroup(t.drillUpButton,"drillUpProxyButton","drillUpProxyGroup",t.langFormat("accessibility.drillUpButton",{chart:t,buttonText:t.getDrilldownBackText()}))},recreateProxyButtonAndGroup:function(t,e,i,n){a(this[i])
this[i]=this.addProxyGroup()
this[e]=this.createProxyButton(t,this[i],{"aria-label":n,tabindex:-1})},getMapZoomNavigation:function(){var t=this.keyCodes,e=this.chart,i=this
return new o(e,{keyCodeMap:[[[t.up,t.down,t.left,t.right],function(t){return i.onMapKbdArrow(this,t)}],[[t.tab],function(t,e){return i.onMapKbdTab(this,e)}],[[t.space,t.enter],function(){return i.onMapKbdClick(this)}]],validate:function(){return!!(e.mapZoom&&e.mapNavButtons&&e.mapNavButtons.length)},init:function(t){return i.onMapNavInit(t)}})},onMapKbdArrow:function(t,e){var i=this.keyCodes
this.chart[e===i.up||e===i.down?"yAxis":"xAxis"][0].panStep(e===i.left||e===i.up?-1:1)
return t.response.success},onMapKbdTab:function(t,e){var i=this.chart
t=t.response
var n=(e=e.shiftKey)&&!this.focusedMapNavButtonIx||!e&&this.focusedMapNavButtonIx
i.mapNavButtons[this.focusedMapNavButtonIx].setState(0)
if(n)return i.mapZoom(),t[e?"prev":"next"]
this.focusedMapNavButtonIx+=e?-1:1
e=i.mapNavButtons[this.focusedMapNavButtonIx]
i.setFocusToElement(e.box,e.element)
e.setState(2)
return t.success},onMapKbdClick:function(t){this.fakeClickEvent(this.chart.mapNavButtons[this.focusedMapNavButtonIx].element)
return t.response.success},onMapNavInit:function(t){var e=this.chart,i=e.mapNavButtons[0],n=e.mapNavButtons[1]
i=0<t?i:n
e.setFocusToElement(i.box,i.element)
i.setState(2)
this.focusedMapNavButtonIx=0<t?0:1},simpleButtonNavigation:function(t,e,i){var n=this.keyCodes,r=this,s=this.chart
return new o(s,{keyCodeMap:[[[n.tab,n.up,n.down,n.left,n.right],function(t,e){return this.response[t===n.tab&&e.shiftKey||t===n.left||t===n.up?"prev":"next"]}],[[n.space,n.enter],function(){var t=i(this,s)
return c(t,this.response.success)}]],validate:function(){return s[t]&&s[t].box&&r[e]},init:function(){s.setFocusToElement(s[t].box,r[e])}})},getKeyboardNavigation:function(){return[this.simpleButtonNavigation("resetZoomButton","resetZoomProxyButton",(function(t,e){e.zoomOut()})),this.simpleButtonNavigation("drillUpButton","drillUpProxyButton",(function(t,e){e.drillUp()
return t.response.prev})),this.getMapZoomNavigation()]}})
return e}))
e(t,"Extensions/RangeSelector.js",[t["Core/Axis/Axis.js"],t["Core/Chart/Chart.js"],t["Core/Globals.js"],t["Core/Options.js"],t["Core/Color/Palette.js"],t["Core/Renderer/SVG/SVGElement.js"],t["Core/Utilities.js"]],(function(t,e,i,n,o,r,s){var a=n.defaultOptions,l=s.addEvent,c=s.createElement,u=s.css,h=s.defined,d=s.destroyObjectProperties,p=s.discardElement,m=s.extend,g=s.find,f=s.fireEvent,b=s.isNumber,y=s.merge,v=s.objectEach,x=s.pad,A=s.pick,w=s.pInt,C=s.splat
m(a,{rangeSelector:{allButtonsEnabled:!1,buttons:void 0,buttonSpacing:5,dropdown:"responsive",enabled:void 0,verticalAlign:"top",buttonTheme:{width:28,height:18,padding:2,zIndex:7},floating:!1,x:0,y:0,height:void 0,inputBoxBorderColor:"none",inputBoxHeight:17,inputBoxWidth:void 0,inputDateFormat:"%b %e, %Y",inputDateParser:void 0,inputEditDateFormat:"%Y-%m-%d",inputEnabled:!0,inputPosition:{align:"right",x:0,y:0},inputSpacing:5,selected:void 0,buttonPosition:{align:"left",x:0,y:0},inputStyle:{color:o.highlightColor80,cursor:"pointer"},labelStyle:{color:o.neutralColor60}}})
m(a.lang,{rangeSelectorZoom:"Zoom",rangeSelectorFrom:"",rangeSelectorTo:"→"})
var T=function(){function e(t){this.buttons=void 0
this.buttonOptions=e.prototype.defaultButtons
this.initialButtonGroupWidth=0
this.options=void 0
this.chart=t
this.init(t)}e.prototype.clickButton=function(e,i){var n=this.chart,o=this.buttonOptions[e],r=n.xAxis[0],s=n.scroller&&n.scroller.getUnionExtremes()||r||{},a=s.dataMin,c=s.dataMax,u=r&&Math.round(Math.min(r.max,A(c,r.max))),d=o.type
s=o._range
var p,m=o.dataGrouping
if(null!==a&&null!==c){n.fixedRange=s
m&&(this.forcedDataGrouping=!0,t.prototype.setDataGrouping.call(r||{chart:this.chart},m,!1),this.frozenStates=o.preserveDataGrouping)
if("month"===d||"year"===d)if(r){d={range:o,max:u,chart:n,dataMin:a,dataMax:c}
var g=r.minFromRange.call(d)
b(d.newMax)&&(u=d.newMax)}else s=o
else if(s)g=Math.max(u-s,a),u=Math.min(g+s,c)
else if("ytd"===d){if(!r){this.deferredYTDClick=e
return}void 0===c&&(a=Number.MAX_VALUE,c=Number.MIN_VALUE,n.series.forEach((function(t){t=t.xData
a=Math.min(t[0],a)
c=Math.max(t[t.length-1],c)})),i=!1),g=p=(u=this.getYTDExtremes(c,a,n.time.useUTC)).min,u=u.max}else"all"===d&&r&&(g=a,u=c)
h(g)&&(g+=o._offsetMin)
h(u)&&(u+=o._offsetMax)
this.setSelected(e)
this.dropdown&&(this.dropdown.selectedIndex=e+1)
if(r)r.setExtremes(g,u,A(i,!0),void 0,{trigger:"rangeSelectorButton",rangeSelectorButton:o})
else{var y=C(n.options.xAxis)[0],v=y.range
y.range=s
var x=y.min
y.min=p
l(n,"load",(function(){y.range=v
y.min=x}))}f(this,"afterBtnClick")}}
e.prototype.setSelected=function(t){this.selected=this.options.selected=t}
e.prototype.init=function(t){var e=this,i=t.options.rangeSelector,n=i.buttons||e.defaultButtons.slice(),o=i.selected,r=function(){var t=e.minInput,i=e.maxInput
t&&t.blur&&f(t,"blur")
i&&i.blur&&f(i,"blur")}
e.chart=t
e.options=i
e.buttons=[]
e.buttonOptions=n
this.eventsToUnbind=[]
this.eventsToUnbind.push(l(t.container,"mousedown",r))
this.eventsToUnbind.push(l(t,"resize",r))
n.forEach(e.computeButtonRange)
void 0!==o&&n[o]&&this.clickButton(o,!1)
this.eventsToUnbind.push(l(t,"load",(function(){t.xAxis&&t.xAxis[0]&&l(t.xAxis[0],"setExtremes",(function(i){this.max-this.min!==t.fixedRange&&"rangeSelectorButton"!==i.trigger&&"updatedData"!==i.trigger&&e.forcedDataGrouping&&!e.frozenStates&&this.setDataGrouping(!1,!1)}))})))}
e.prototype.updateButtonStates=function(){var t=this,e=this.chart,i=this.dropdown,n=e.xAxis[0],o=Math.round(n.max-n.min),r=!n.hasVisibleSeries,s=e.scroller&&e.scroller.getUnionExtremes()||n,a=s.dataMin,l=s.dataMax,c=(e=t.getYTDExtremes(l,a,e.time.useUTC)).min,u=e.max,h=t.selected,d=b(h),p=t.options.allButtonsEnabled,m=t.buttons
t.buttonOptions.forEach((function(e,s){var g=e._range,f=e.type,b=e.count||1,y=m[s],v=0,x=e._offsetMax-e._offsetMin
e=s===h
var A=g>l-a,w=g<n.minRange,C=!1,T=!1
g=g===o;("month"===f||"year"===f)&&o+36e5>=864e5*{month:28,year:365}[f]*b-x&&o-36e5<=864e5*{month:31,year:366}[f]*b+x?g=!0:"ytd"===f?(g=u-c+x===o,C=!e):"all"===f&&(g=n.max-n.min>=l-a,T=!e&&d&&g)
f=!p&&(A||w||T||r)
b=e&&g||g&&!d&&!C||e&&t.frozenStates
f?v=3:b&&(d=!0,v=2)
y.state!==v&&(y.setState(v),i&&(i.options[s+1].disabled=f,2===v&&(i.selectedIndex=s+1)),0===v&&h===s&&t.setSelected())}))}
e.prototype.computeButtonRange=function(t){var e=t.type,i=t.count||1,n={millisecond:1,second:1e3,minute:6e4,hour:36e5,day:864e5,week:6048e5}
n[e]?t._range=n[e]*i:"month"!==e&&"year"!==e||(t._range=864e5*{month:30,year:365}[e]*i)
t._offsetMin=A(t.offsetMin,0)
t._offsetMax=A(t.offsetMax,0)
t._range+=t._offsetMax-t._offsetMin}
e.prototype.getInputValue=function(t){t="min"===t?this.minInput:this.maxInput
var e=this.chart.options.rangeSelector,i=this.chart.time
return t?("text"===t.type&&e.inputDateParser||this.defaultInputDateParser)(t.value,i.useUTC,i):0}
e.prototype.setInputValue=function(t,e){var i=this.options,n=this.chart.time,o="min"===t?this.minInput:this.maxInput
t="min"===t?this.minDateBox:this.maxDateBox
if(o){var r=o.getAttribute("data-hc-time")
r=h(r)?Number(r):void 0
h(e)&&(h(r)&&o.setAttribute("data-hc-time-previous",r),o.setAttribute("data-hc-time",e),r=e)
o.value=n.dateFormat(this.inputTypeFormats[o.type]||i.inputEditDateFormat,r)
t&&t.attr({text:n.dateFormat(i.inputDateFormat,r)})}}
e.prototype.setInputExtremes=function(t,e,i){if(t="min"===t?this.minInput:this.maxInput){var n=this.inputTypeFormats[t.type],o=this.chart.time
n&&(e=o.dateFormat(n,e),t.min!==e&&(t.min=e),i=o.dateFormat(n,i),t.max!==i&&(t.max=i))}}
e.prototype.showInput=function(t){var e="min"===t?this.minDateBox:this.maxDateBox
if((t="min"===t?this.minInput:this.maxInput)&&e&&this.inputGroup){var i="text"===t.type,n=this.inputGroup,o=n.translateX
n=n.translateY
u(t,{width:i?e.width-2+"px":"auto",height:i?e.height-2+"px":"auto",border:"2px solid silver"})
u(t,i?{left:o+e.x+"px",top:n+"px"}:{left:Math.min(Math.round(e.x+o-(t.offsetWidth-e.width)/2),this.chart.chartWidth-t.offsetWidth)+"px",top:n-(t.offsetHeight-e.height)/2+"px"})}}
e.prototype.hideInput=function(t){(t="min"===t?this.minInput:this.maxInput)&&u(t,{top:"-9999em",border:0,width:"1px",height:"1px"})}
e.prototype.defaultInputDateParser=function(t,e,n){var o=t.split("/").join("-").split(" ").join("T");-1===o.indexOf("T")&&(o+="T00:00")
if(e)o+="Z"
else{var r;(r=i.isSafari)&&(r=!(6<(r=o).length&&(r.lastIndexOf("-")===r.length-6||r.lastIndexOf("+")===r.length-6)))
r&&(o+=0>=(r=new Date(o).getTimezoneOffset()/60)?"+"+x(-r)+":00":"-"+x(r)+":00")}o=Date.parse(o)
b(o)||(t=t.split("-"),o=Date.UTC(w(t[0]),w(t[1])-1,w(t[2])))
n&&e&&(o+=n.getTimezoneOffset(o))
return o}
e.prototype.drawInput=function(t){function e(){var e=l.getInputValue(t),i=n.xAxis[0],o=n.scroller&&n.scroller.xAxis?n.scroller.xAxis:i,r=o.dataMin
o=o.dataMax
var s=l.maxInput,a=l.minInput
e!==Number(v.getAttribute("data-hc-time-previous"))&&b(e)&&(v.setAttribute("data-hc-time-previous",e),g&&s&&b(r)?e>Number(s.getAttribute("data-hc-time"))?e=void 0:e<r&&(e=r):a&&b(o)&&(e<Number(a.getAttribute("data-hc-time"))?e=void 0:e>o&&(e=o)),void 0!==e&&i.setExtremes(g?e:i.min,g?i.max:e,void 0,void 0,{trigger:"rangeSelectorInput"}))}var n=this.chart,r=this.div,s=this.inputGroup,l=this,h=n.renderer.style||{},d=n.renderer,p=n.options.rangeSelector,g="min"===t,f=a.lang[g?"rangeSelectorFrom":"rangeSelectorTo"]
f=d.label(f,0).addClass("highcharts-range-label").attr({padding:f?2:0}).add(s)
d=d.label("",0).addClass("highcharts-range-input").attr({padding:2,width:p.inputBoxWidth,height:p.inputBoxHeight,"text-align":"center"}).on("click",(function(){l.showInput(t)
l[t+"Input"].focus()}))
n.styledMode||d.attr({stroke:p.inputBoxBorderColor,"stroke-width":1})
d.add(s)
var v=c("input",{name:t,className:"highcharts-range-selector"},void 0,r)
v.setAttribute("type",function(t){if(-1!==t.indexOf("%L"))return"text"
var e="aAdewbBmoyY".split("").some((function(e){return-1!==t.indexOf("%"+e)})),i="HkIlMS".split("").some((function(e){return-1!==t.indexOf("%"+e)}))
return e&&i?"datetime-local":e?"date":i?"time":"text"}(p.inputDateFormat||"%b %e, %Y"))
n.styledMode||(f.css(y(h,p.labelStyle)),d.css(y({color:o.neutralColor80},h,p.inputStyle)),u(v,m({position:"absolute",border:0,boxShadow:"0 0 15px rgba(0,0,0,0.3)",width:"1px",height:"1px",padding:0,textAlign:"center",fontSize:h.fontSize,fontFamily:h.fontFamily,top:"-9999em"},p.inputStyle)))
v.onfocus=function(){l.showInput(t)}
v.onblur=function(){v===i.doc.activeElement&&e()
l.hideInput(t)
l.setInputValue(t)
v.blur()}
var x=!1
v.onchange=function(){e()
x||(l.hideInput(t),v.blur())}
v.onkeypress=function(t){13===t.keyCode&&e()}
v.onkeydown=function(){x=!0}
v.onkeyup=function(){x=!1}
return{dateBox:d,input:v,label:f}}
e.prototype.getPosition=function(){var t=this.chart,e=t.options.rangeSelector
return{buttonTop:(t="top"===e.verticalAlign?t.plotTop-t.axisOffset[0]:0)+e.buttonPosition.y,inputTop:t+e.inputPosition.y-10}}
e.prototype.getYTDExtremes=function(t,e,i){var n=this.chart.time,o=new n.Date(t),r=n.get("FullYear",o)
i=i?n.Date.UTC(r,0,1):+new n.Date(r,0,1)
e=Math.max(e,i)
o=o.getTime()
return{max:Math.min(t||o,o),min:e}}
e.prototype.render=function(t,e){var i=this.chart,n=i.renderer,o=i.container,r=i.options,s=r.rangeSelector,a=A(r.chart.style&&r.chart.style.zIndex,0)+1
r=s.inputEnabled
if(!1!==s.enabled){this.rendered||(this.group=n.g("range-selector-group").attr({zIndex:7}).add(),this.div=c("div",void 0,{position:"relative",height:0,zIndex:a}),this.buttonOptions.length&&this.renderButtons(),o.parentNode&&o.parentNode.insertBefore(this.div,o),r&&(this.inputGroup=n.g("input-group").add(this.group),n=this.drawInput("min"),this.minDateBox=n.dateBox,this.minLabel=n.label,this.minInput=n.input,n=this.drawInput("max"),this.maxDateBox=n.dateBox,this.maxLabel=n.label,this.maxInput=n.input))
if(r&&(this.setInputValue("min",t),this.setInputValue("max",e),t=i.scroller&&i.scroller.getUnionExtremes()||i.xAxis[0]||{},h(t.dataMin)&&h(t.dataMax)&&(i=i.xAxis[0].minRange||0,this.setInputExtremes("min",t.dataMin,Math.min(t.dataMax,this.getInputValue("max"))-i),this.setInputExtremes("max",Math.max(t.dataMin,this.getInputValue("min"))+i,t.dataMax)),this.inputGroup)){var l=0;[this.minLabel,this.minDateBox,this.maxLabel,this.maxDateBox].forEach((function(t){t&&t.width&&(t.attr({x:l}),l+=t.width+s.inputSpacing)}))}this.alignElements()
this.rendered=!0}}
e.prototype.renderButtons=function(){var t=this,e=this.buttons,n=this.options,o=a.lang,r=this.chart.renderer,s=y(n.buttonTheme),u=s&&s.states,h=s.width||28
delete s.width
this.buttonGroup=r.g("range-selector-buttons").add(this.group)
var d=this.dropdown=c("select",void 0,{position:"absolute",width:"1px",height:"1px",padding:0,border:0,top:"-9999em",cursor:"pointer",opacity:1e-4},this.div)
l(d,"touchstart",(function(){d.style.fontSize="16px"}));[[i.isMS?"mouseover":"mouseenter"],[i.isMS?"mouseout":"mouseleave"],["change","click"]].forEach((function(i){var n=i[0],o=i[1]
l(d,n,(function(){var i=e[t.currentButtonIndex()]
i&&f(i.element,o||n)}))}))
this.zoomText=r.text(o.rangeSelectorZoom,0,15).add(this.buttonGroup)
this.chart.styledMode||(this.zoomText.css(n.labelStyle),s["stroke-width"]=A(s["stroke-width"],0))
c("option",{textContent:this.zoomText.textStr,disabled:!0},void 0,d)
this.buttonOptions.forEach((function(i,n){c("option",{textContent:i.title||i.text},void 0,d)
e[n]=r.button(i.text,0,0,(function(e){var o,r=i.events&&i.events.click
r&&(o=r.call(i,e))
!1!==o&&t.clickButton(n)
t.isActive=!0}),s,u&&u.hover,u&&u.select,u&&u.disabled).attr({"text-align":"center",width:h}).add(t.buttonGroup)
i.title&&e[n].attr("title",i.title)}))}
e.prototype.alignElements=function(){var t=this,e=this.buttonGroup,i=this.buttons,n=this.chart,o=this.group,r=this.inputGroup,s=this.options,a=this.zoomText,l=n.options,c=l.exporting&&!1!==l.exporting.enabled&&l.navigation&&l.navigation.buttonOptions
l=s.buttonPosition
var u=s.inputPosition,h=s.verticalAlign,d=function(e,i){return c&&t.titleCollision(n)&&"top"===h&&"right"===i.align&&i.y-e.getBBox().height-12<(c.y||0)+(c.height||0)+n.spacing[0]?-40:0},p=n.plotLeft
if(o&&l&&u){var m=l.x-n.spacing[3]
if(e){this.positionButtons()
if(!this.initialButtonGroupWidth){var g=0
a&&(g+=a.getBBox().width+5)
i.forEach((function(t,e){g+=t.width
e!==i.length-1&&(g+=s.buttonSpacing)}))
this.initialButtonGroupWidth=g}p-=n.spacing[3]
this.updateButtonStates()
a=d(e,l)
this.alignButtonGroup(a)
o.placed=e.placed=n.hasLoaded}e=0
r&&(e=d(r,u),"left"===u.align?m=p:"right"===u.align&&(m=-Math.max(n.axisOffset[1],-e)),r.align({y:u.y,width:r.getBBox().width,align:u.align,x:u.x+m-2},!0,n.spacingBox),r.placed=n.hasLoaded)
this.handleCollision(e)
o.align({verticalAlign:h},!0,n.spacingBox)
r=o.alignAttr.translateY
e=o.getBBox().height+20
d=0
"bottom"===h&&(d=r-(e=e+(d=(d=n.legend&&n.legend.options)&&"bottom"===d.verticalAlign&&d.enabled&&!d.floating?n.legend.legendHeight+A(d.margin,10):0)-20)-(s.floating?0:s.y)-(n.titleOffset?n.titleOffset[2]:0)-10)
"top"===h?(s.floating&&(d=0),n.titleOffset&&n.titleOffset[0]&&(d=n.titleOffset[0]),d+=n.margin[0]-n.spacing[0]||0):"middle"===h&&(u.y===l.y?d=r:(u.y||l.y)&&(d=0>u.y||0>l.y?d-Math.min(u.y,l.y):r-e))
o.translate(s.x,s.y+Math.floor(d))
l=this.minInput
u=this.maxInput
r=this.dropdown
s.inputEnabled&&l&&u&&(l.style.marginTop=o.translateY+"px",u.style.marginTop=o.translateY+"px")
r&&(r.style.marginTop=o.translateY+"px")}}
e.prototype.alignButtonGroup=function(t,e){var i=this.chart,n=this.buttonGroup,o=this.options.buttonPosition,r=i.plotLeft-i.spacing[3],s=o.x-i.spacing[3]
"right"===o.align?s+=t-r:"center"===o.align&&(s-=r/2)
n&&n.align({y:o.y,width:A(e,this.initialButtonGroupWidth),align:o.align,x:s},!0,i.spacingBox)}
e.prototype.positionButtons=function(){var t=this.buttons,e=this.chart,i=this.options,n=this.zoomText,o=e.hasLoaded?"animate":"attr",r=i.buttonPosition,s=e.plotLeft,a=s
n&&"hidden"!==n.visibility&&(n[o]({x:A(s+r.x,s)}),a+=r.x+n.getBBox().width+5)
this.buttonOptions.forEach((function(e,n){"hidden"!==t[n].visibility?(t[n][o]({x:a}),a+=t[n].width+i.buttonSpacing):t[n][o]({x:s})}))}
e.prototype.handleCollision=function(t){var e=this,i=this.chart,n=this.buttonGroup,o=this.inputGroup,r=this.options,s=r.buttonPosition,a=r.dropdown,l=r.inputPosition
r=function(){var t=0
e.buttons.forEach((function(e){(e=e.getBBox()).width>t&&(t=e.width)}))
return t}
var c=function(e){if(o&&n){var i=o.alignAttr.translateX+o.alignOptions.x-t+o.getBBox().x+2,r=o.alignOptions.width,a=n.alignAttr.translateX+n.getBBox().x
return a+e>i&&i+r>a&&s.y<l.y+o.getBBox().height}return!1},u=function(){o&&n&&o.attr({translateX:o.alignAttr.translateX+(i.axisOffset[1]>=-t?0:-t),translateY:o.alignAttr.translateY+n.getBBox().height+10})}
if(n){if("always"===a){this.collapseButtons(t)
c(r())&&u()
return}"never"===a&&this.expandButtons()}o&&n?l.align===s.align||c(this.initialButtonGroupWidth+20)?"responsive"===a?(this.collapseButtons(t),c(r())&&u()):u():"responsive"===a&&this.expandButtons():n&&"responsive"===a&&(this.initialButtonGroupWidth>i.plotWidth?this.collapseButtons(t):this.expandButtons())}
e.prototype.collapseButtons=function(t){var e,i=this.buttons,n=this.buttonOptions,o=this.dropdown,r=this.options,s=this.zoomText,a=function(t){return{text:t?t+" ▾":"▾",width:"auto",paddingLeft:8,paddingRight:8}}
s&&s.hide()
var l=!1
n.forEach((function(t,e){2!==(e=i[e]).state?e.hide():(e.show(),e.attr(a(t.text)),l=!0)}))
l||(o&&(o.selectedIndex=0),i[0].show(),i[0].attr(a(null===(e=this.zoomText)||void 0===e?void 0:e.textStr)))
e=r.buttonPosition.align
this.positionButtons()
"right"!==e&&"center"!==e||this.alignButtonGroup(t,i[this.currentButtonIndex()].getBBox().width)
this.showDropdown()}
e.prototype.expandButtons=function(){var t=this.buttons,e=this.buttonOptions,i=this.options,n=this.zoomText
this.hideDropdown()
n&&n.show()
e.forEach((function(e,n){(n=t[n]).show()
n.attr({text:e.text,width:i.buttonTheme.width||28,paddingLeft:"unset",paddingRight:"unset"})
2>n.state&&n.setState(0)}))
this.positionButtons()}
e.prototype.currentButtonIndex=function(){var t=this.dropdown
return t&&0<t.selectedIndex?t.selectedIndex-1:0}
e.prototype.showDropdown=function(){var t=this.buttonGroup,e=this.buttons,i=this.chart,n=this.dropdown
if(t&&n){var o=t.translateX
t=t.translateY
e=e[this.currentButtonIndex()].getBBox()
u(n,{left:i.plotLeft+o+"px",top:t+.5+"px",width:e.width+"px",height:e.height+"px"})
this.hasVisibleDropdown=!0}}
e.prototype.hideDropdown=function(){var t=this.dropdown
t&&(u(t,{top:"-9999em",width:"1px",height:"1px"}),this.hasVisibleDropdown=!1)}
e.prototype.getHeight=function(){var t=this.options,e=this.group,i=t.y,n=t.buttonPosition.y,o=t.inputPosition.y
if(t.height)return t.height
this.alignElements()
t=e?e.getBBox(!0).height+13+i:0
e=Math.min(o,n);(0>o&&0>n||0<o&&0<n)&&(t+=Math.abs(e))
return t}
e.prototype.titleCollision=function(t){return!(t.options.title.text||t.options.subtitle.text)}
e.prototype.update=function(t){var e=this.chart
y(!0,e.options.rangeSelector,t)
this.destroy()
this.init(e)
this.render()}
e.prototype.destroy=function(){var t=this,i=t.minInput,n=t.maxInput
t.eventsToUnbind&&(t.eventsToUnbind.forEach((function(t){return t()})),t.eventsToUnbind=void 0)
d(t.buttons)
i&&(i.onfocus=i.onblur=i.onchange=null)
n&&(n.onfocus=n.onblur=n.onchange=null)
v(t,(function(i,n){i&&"chart"!==n&&(i instanceof r?i.destroy():i instanceof window.HTMLElement&&p(i))
i!==e.prototype[n]&&(t[n]=null)}),this)}
return e}()
T.prototype.defaultButtons=[{type:"month",count:1,text:"1m",title:"View 1 month"},{type:"month",count:3,text:"3m",title:"View 3 months"},{type:"month",count:6,text:"6m",title:"View 6 months"},{type:"ytd",text:"YTD",title:"View year to date"},{type:"year",count:1,text:"1y",title:"View 1 year"},{type:"all",text:"All",title:"View all"}]
T.prototype.inputTypeFormats={"datetime-local":"%Y-%m-%dT%H:%M:%S",date:"%Y-%m-%d",time:"%H:%M:%S"}
t.prototype.minFromRange=function(){var t=this.range,e=t.type,i=this.max,n=this.chart.time,o=function(t,i){var o="year"===e?"FullYear":"Month",r=new n.Date(t),s=n.get(o,r)
n.set(o,r,s+i)
s===n.get(o,r)&&n.set("Date",r,0)
return r.getTime()-t}
if(b(t))var r=i-t,s=t
else r=i+o(i,-t.count),this.chart&&(this.chart.fixedRange=i-r)
var a=A(this.dataMin,Number.MIN_VALUE)
b(r)||(r=a)
r<=a&&(r=a,void 0===s&&(s=o(r,t.count)),this.newMax=Math.min(r+s,this.dataMax))
b(i)||(r=void 0)
return r}
if(!i.RangeSelector){var E=[],S=function(t){function e(){s&&(i=t.xAxis[0].getExtremes(),n=t.legend,r=null==s?void 0:s.options.verticalAlign,b(i.min)&&s.render(i.min,i.max),n.display&&"top"===r&&r===n.options.verticalAlign&&((o=y(t.spacingBox)).y="vertical"===n.options.layout?t.plotTop:o.y+s.getHeight(),n.group.placed=!1,n.align(o)))}var i,n,o,r,s=t.rangeSelector
s&&(g(E,(function(e){return e[0]===t}))||E.push([t,[l(t.xAxis[0],"afterSetExtremes",(function(t){s&&s.render(t.min,t.max)})),l(t,"redraw",e)]]),e())}
l(e,"afterGetContainer",(function(){var t
null!==(t=this.options.rangeSelector)&&void 0!==t&&t.enabled&&(this.rangeSelector=new T(this))}))
l(e,"beforeRender",(function(){var t=this.axes,e=this.rangeSelector
e&&(b(e.deferredYTDClick)&&(e.clickButton(e.deferredYTDClick),delete e.deferredYTDClick),t.forEach((function(t){t.updateNames()
t.setScale()})),this.getAxisMargins(),e.render(),t=e.options.verticalAlign,e.options.floating||("bottom"===t?this.extraBottomMargin=!0:"middle"!==t&&(this.extraTopMargin=!0)))}))
l(e,"update",(function(t){var e=t.options.rangeSelector
t=this.rangeSelector
var i=this.extraBottomMargin,n=this.extraTopMargin
e&&e.enabled&&!h(t)&&this.options.rangeSelector&&(this.options.rangeSelector.enabled=!0,this.rangeSelector=t=new T(this))
this.extraTopMargin=this.extraBottomMargin=!1
t&&(S(this),e=e&&e.verticalAlign||t.options&&t.options.verticalAlign,t.options.floating||("bottom"===e?this.extraBottomMargin=!0:"middle"!==e&&(this.extraTopMargin=!0)),this.extraBottomMargin!==i||this.extraTopMargin!==n)&&(this.isDirtyBox=!0)}))
l(e,"render",(function(){var t=this.rangeSelector
t&&!t.options.floating&&(t.render(),"bottom"===(t=t.options.verticalAlign)?this.extraBottomMargin=!0:"middle"!==t&&(this.extraTopMargin=!0))}))
l(e,"getMargins",(function(){var t=this.rangeSelector
t&&(t=t.getHeight(),this.extraTopMargin&&(this.plotTop+=t),this.extraBottomMargin&&(this.marginBottom+=t))}))
e.prototype.callbacks.push(S)
l(e,"destroy",(function(){for(var t=0;t<E.length;t++){var e=E[t]
if(e[0]===this){e[1].forEach((function(t){return t()}))
E.splice(t,1)
break}}}))
i.RangeSelector=T}return i.RangeSelector}))
e(t,"Accessibility/Components/RangeSelectorComponent.js",[t["Accessibility/AccessibilityComponent.js"],t["Accessibility/Utils/ChartUtilities.js"],t["Accessibility/Utils/Announcer.js"],t["Core/Globals.js"],t["Accessibility/Utils/HTMLUtilities.js"],t["Accessibility/KeyboardNavigationHandler.js"],t["Core/Utilities.js"],t["Extensions/RangeSelector.js"]],(function(t,e,i,n,o,r,s,a){var l=e.unhideChartElementFromAT,c=e.getAxisRangeDescription,u=o.setElAttrs,h=s.addEvent
e=s.extend
n.Chart.prototype.highlightRangeSelectorButton=function(t){var e,i,n=(null===(e=this.rangeSelector)||void 0===e?void 0:e.buttons)||[]
e=this.highlightedRangeSelectorItemIx
var o=null===(i=this.rangeSelector)||void 0===i?void 0:i.selected
void 0!==e&&n[e]&&e!==o&&n[e].setState(this.oldRangeSelectorItemState||0)
this.highlightedRangeSelectorItemIx=t
return!!n[t]&&(this.setFocusToElement(n[t].box,n[t].element),t!==o&&(this.oldRangeSelectorItemState=n[t].state,n[t].setState(1)),!0)}
h(a,"afterBtnClick",(function(){var t,e=null===(t=this.chart.accessibility)||void 0===t?void 0:t.components.rangeSelector
return null==e?void 0:e.onAfterBtnClick()}));(n=function(){}).prototype=new t
e(n.prototype,{init:function(){this.announcer=new i(this.chart,"polite")},onChartUpdate:function(){var t,e=this.chart,i=this,n=e.rangeSelector
n&&(this.updateSelectorVisibility(),this.setDropdownAttrs(),(null===(t=n.buttons)||void 0===t?0:t.length)&&n.buttons.forEach((function(t){i.setRangeButtonAttrs(t)})),n.maxInput&&n.minInput&&["minInput","maxInput"].forEach((function(t,o){(t=n[t])&&(l(e,t),i.setRangeInputAttrs(t,"accessibility.rangeSelector."+(o?"max":"min")+"InputLabel"))})))},updateSelectorVisibility:function(){var t=this.chart,e=t.rangeSelector,i=null==e?void 0:e.dropdown,n=(null==e?void 0:e.buttons)||[]
null!=e&&e.hasVisibleDropdown&&i?(l(t,i),n.forEach((function(t){return t.element.setAttribute("aria-hidden",!0)}))):(i&&i.setAttribute("aria-hidden",!0),n.forEach((function(e){return l(t,e.element)})))},setDropdownAttrs:function(){var t,e=this.chart,i=null===(t=e.rangeSelector)||void 0===t?void 0:t.dropdown
i&&(t=e.langFormat("accessibility.rangeSelector.dropdownLabel",{rangeTitle:e.options.lang.rangeSelectorZoom}),i.setAttribute("aria-label",t),i.setAttribute("tabindex",-1))},setRangeButtonAttrs:function(t){u(t.element,{tabindex:-1,role:"button"})},setRangeInputAttrs:function(t,e){var i=this.chart
u(t,{tabindex:-1,"aria-label":i.langFormat(e,{chart:i})})},onButtonNavKbdArrowKey:function(t,e){var i=t.response,n=this.keyCodes,o=this.chart,r=o.options.accessibility.keyboardNavigation.wrapAround
e=e===n.left||e===n.up?-1:1
return o.highlightRangeSelectorButton(o.highlightedRangeSelectorItemIx+e)?i.success:r?(t.init(e),i.success):i[0<e?"next":"prev"]},onButtonNavKbdClick:function(t){t=t.response
var e=this.chart
3!==e.oldRangeSelectorItemState&&this.fakeClickEvent(e.rangeSelector.buttons[e.highlightedRangeSelectorItemIx].element)
return t.success},onAfterBtnClick:function(){var t=this.chart,e=c(t.xAxis[0]);(t=t.langFormat("accessibility.rangeSelector.clickButtonAnnouncement",{chart:t,axisRangeDescription:e}))&&this.announcer.announce(t)},onInputKbdMove:function(t){var e,i,n=this.chart,o=n.rangeSelector,r=n.highlightedInputRangeIx=(n.highlightedInputRangeIx||0)+t
1<r||0>r?(null===(e=n.accessibility)||void 0===e||e.keyboardNavigation.tabindexContainer.focus(),null===(i=n.accessibility)||void 0===i||i.keyboardNavigation[0>t?"prev":"next"]()):o&&(t=o[r?"maxDateBox":"minDateBox"],o=o[r?"maxInput":"minInput"],t&&o&&n.setFocusToElement(t,o))},onInputNavInit:function(t){var e=this,i=this,n=this.chart,o=0<t?0:1,r=n.rangeSelector,s=null==r?void 0:r[o?"maxDateBox":"minDateBox"]
t=null==r?void 0:r.minInput
r=null==r?void 0:r.maxInput
n.highlightedInputRangeIx=o
if(s&&t&&r){n.setFocusToElement(s,o?r:t)
this.removeInputKeydownHandler&&this.removeInputKeydownHandler()
n=function(t){(t.which||t.keyCode)===e.keyCodes.tab&&(t.preventDefault(),t.stopPropagation(),i.onInputKbdMove(t.shiftKey?-1:1))}
var a=h(t,"keydown",n),l=h(r,"keydown",n)
this.removeInputKeydownHandler=function(){a()
l()}}},onInputNavTerminate:function(){var t=this.chart.rangeSelector||{}
t.maxInput&&t.hideInput("max")
t.minInput&&t.hideInput("min")
this.removeInputKeydownHandler&&(this.removeInputKeydownHandler(),delete this.removeInputKeydownHandler)},initDropdownNav:function(){var t=this,e=this.chart,i=e.rangeSelector,n=null==i?void 0:i.dropdown
i&&n&&(e.setFocusToElement(i.buttonGroup,n),this.removeDropdownKeydownHandler&&this.removeDropdownKeydownHandler(),this.removeDropdownKeydownHandler=h(n,"keydown",(function(i){var n,o;(i.which||i.keyCode)===t.keyCodes.tab&&(i.preventDefault(),i.stopPropagation(),null===(n=e.accessibility)||void 0===n||n.keyboardNavigation.tabindexContainer.focus(),null===(o=e.accessibility)||void 0===o||o.keyboardNavigation[i.shiftKey?"prev":"next"]())})))},getRangeSelectorButtonNavigation:function(){var t=this.chart,e=this.keyCodes,i=this
return new r(t,{keyCodeMap:[[[e.left,e.right,e.up,e.down],function(t){return i.onButtonNavKbdArrowKey(this,t)}],[[e.enter,e.space],function(){return i.onButtonNavKbdClick(this)}]],validate:function(){var e,i
return!(null===(i=null===(e=t.rangeSelector)||void 0===e?void 0:e.buttons)||void 0===i||!i.length)},init:function(e){var n=t.rangeSelector
null!=n&&n.hasVisibleDropdown?i.initDropdownNav():n&&(n=n.buttons.length-1,t.highlightRangeSelectorButton(0<e?0:n))},terminate:function(){i.removeDropdownKeydownHandler&&(i.removeDropdownKeydownHandler(),delete i.removeDropdownKeydownHandler)}})},getRangeSelectorInputNavigation:function(){var t=this.chart,e=this
return new r(t,{keyCodeMap:[],validate:function(){return!!(t.rangeSelector&&t.rangeSelector.inputGroup&&"hidden"!==t.rangeSelector.inputGroup.element.getAttribute("visibility")&&!1!==t.options.rangeSelector.inputEnabled&&t.rangeSelector.minInput&&t.rangeSelector.maxInput)},init:function(t){e.onInputNavInit(t)},terminate:function(){e.onInputNavTerminate()}})},getKeyboardNavigation:function(){return[this.getRangeSelectorButtonNavigation(),this.getRangeSelectorInputNavigation()]},destroy:function(){var t
this.removeDropdownKeydownHandler&&this.removeDropdownKeydownHandler()
this.removeInputKeydownHandler&&this.removeInputKeydownHandler()
null===(t=this.announcer)||void 0===t||t.destroy()}})
return n}))
e(t,"Accessibility/Components/InfoRegionsComponent.js",[t["Core/Globals.js"],t["Core/Renderer/HTML/AST.js"],t["Core/Utilities.js"],t["Accessibility/AccessibilityComponent.js"],t["Accessibility/Utils/Announcer.js"],t["Accessibility/Components/AnnotationsA11y.js"],t["Accessibility/Utils/ChartUtilities.js"],t["Accessibility/Utils/HTMLUtilities.js"]],(function(t,e,i,n,o,r,s,a){var l=t.doc,c=i.extend,u=i.format,h=i.pick,d=r.getAnnotationsInfoHTML,p=s.getAxisDescription,m=s.getAxisRangeDescription,g=s.getChartTitle,f=s.unhideChartElementFromAT,b=a.addClass,y=a.getElement,v=a.getHeadingTagNameForElement,x=a.setElAttrs,A=a.stripHTMLTagsFromString,w=a.visuallyHideElement
t.Chart.prototype.getTypeDescription=function(t){var e=t[0],i=this.series&&this.series[0]||{}
i={numSeries:this.series.length,numPoints:i.points&&i.points.length,chart:this,mapTitle:i.mapTitle}
if(!e)return this.langFormat("accessibility.chartTypes.emptyChart",i)
if("map"===e)return i.mapTitle?this.langFormat("accessibility.chartTypes.mapTypeDescription",i):this.langFormat("accessibility.chartTypes.unknownMap",i)
if(1<this.types.length)return this.langFormat("accessibility.chartTypes.combinationChart",i)
t=t[0]
e=this.langFormat("accessibility.seriesTypeDescriptions."+t,i)
var n=this.series&&2>this.series.length?"Single":"Multiple"
return(this.langFormat("accessibility.chartTypes."+t+n,i)||this.langFormat("accessibility.chartTypes.default"+n,i))+(e?" "+e:"")};(i=function(){}).prototype=new n
c(i.prototype,{init:function(){var t=this.chart,e=this
this.initRegionsDefinitions()
this.addEvent(t,"aftergetTableAST",(function(t){e.onDataTableCreated(t)}))
this.addEvent(t,"afterViewData",(function(t){e.dataTableDiv=t
setTimeout((function(){e.focusDataTable()}),300)}))
this.announcer=new o(t,"assertive")},initRegionsDefinitions:function(){var t=this
this.screenReaderSections={before:{element:null,buildContent:function(e){var i=e.options.accessibility.screenReaderSection.beforeChartFormatter
return i?i(e):t.defaultBeforeChartFormatter(e)},insertIntoDOM:function(t,e){e.renderTo.insertBefore(t,e.renderTo.firstChild)},afterInserted:function(){void 0!==t.sonifyButtonId&&t.initSonifyButton(t.sonifyButtonId)
void 0!==t.dataTableButtonId&&t.initDataTableButton(t.dataTableButtonId)}},after:{element:null,buildContent:function(e){var i=e.options.accessibility.screenReaderSection.afterChartFormatter
return i?i(e):t.defaultAfterChartFormatter()},insertIntoDOM:function(t,e){e.renderTo.insertBefore(t,e.container.nextSibling)}}}},onChartRender:function(){var t=this
this.linkedDescriptionElement=this.getLinkedDescriptionElement()
this.setLinkedDescriptionAttrs()
Object.keys(this.screenReaderSections).forEach((function(e){t.updateScreenReaderSection(e)}))},getLinkedDescriptionElement:function(){var t=this.chart.options.accessibility.linkedDescription
if(t){if("string"!=typeof t)return t
t=u(t,this.chart)
if(1===(t=l.querySelectorAll(t)).length)return t[0]}},setLinkedDescriptionAttrs:function(){var t=this.linkedDescriptionElement
t&&(t.setAttribute("aria-hidden","true"),b(t,"highcharts-linked-description"))},updateScreenReaderSection:function(t){var i=this.chart,n=this.screenReaderSections[t],o=n.buildContent(i),r=n.element=n.element||this.createElement("div"),s=r.firstChild||this.createElement("div")
this.setScreenReaderSectionAttribs(r,t)
e.setElementHTML(s,o)
r.appendChild(s)
n.insertIntoDOM(r,i)
w(s)
f(i,s)
n.afterInserted&&n.afterInserted()},setScreenReaderSectionAttribs:function(t,e){var i=this.chart,n=i.langFormat("accessibility.screenReaderSection."+e+"RegionLabel",{chart:i})
x(t,{id:"highcharts-screen-reader-region-"+e+"-"+i.index,"aria-label":n})
t.style.position="relative"
"all"===i.options.accessibility.landmarkVerbosity&&n&&t.setAttribute("role","region")},defaultBeforeChartFormatter:function(){var e,i=this.chart,n=i.options.accessibility.screenReaderSection.beforeChartFormat,o=this.getAxesDescription(),r=i.sonify&&(null===(e=i.options.sonification)||void 0===e?void 0:e.enabled)
e="highcharts-a11y-sonify-data-btn-"+i.index
var s="hc-linkto-highcharts-data-table-"+i.index,a=d(i),l=i.langFormat("accessibility.screenReaderSection.annotations.heading",{chart:i})
o={headingTagName:v(i.renderTo),chartTitle:g(i),typeDescription:this.getTypeDescriptionText(),chartSubtitle:this.getSubtitleText(),chartLongdesc:this.getLongdescText(),xAxisDescription:o.xAxis,yAxisDescription:o.yAxis,playAsSoundButton:r?this.getSonifyButtonText(e):"",viewTableButton:i.getCSV?this.getDataTableButtonText(s):"",annotationsTitle:a?l:"",annotationsList:a}
i=t.i18nFormat(n,o,i)
this.dataTableButtonId=s
this.sonifyButtonId=e
return i.replace(/<(\w+)[^>]*?>\s*<\/\1>/g,"")},defaultAfterChartFormatter:function(){var e=this.chart,i=e.options.accessibility.screenReaderSection.afterChartFormat,n={endOfChartMarker:this.getEndOfChartMarkerText()}
return t.i18nFormat(i,n,e).replace(/<(\w+)[^>]*?>\s*<\/\1>/g,"")},getLinkedDescription:function(){var t=this.linkedDescriptionElement
return A(t&&t.innerHTML||"")},getLongdescText:function(){var t=this.chart.options,e=t.caption
e=e&&e.text
var i=this.getLinkedDescription()
return t.accessibility.description||i||e||""},getTypeDescriptionText:function(){var t=this.chart
return t.types?t.options.accessibility.typeDescription||t.getTypeDescription(t.types):""},getDataTableButtonText:function(t){var e=this.chart
return'<button id="'+t+'">'+(e=e.langFormat("accessibility.table.viewAsDataTableButtonText",{chart:e,chartTitle:g(e)}))+"</button>"},getSonifyButtonText:function(t){var e,i=this.chart
return!1===(null===(e=i.options.sonification)||void 0===e?void 0:e.enabled)?"":'<button id="'+t+'">'+(e=i.langFormat("accessibility.sonification.playAsSoundButtonText",{chart:i,chartTitle:g(i)}))+"</button>"},getSubtitleText:function(){var t=this.chart.options.subtitle
return A(t&&t.text||"")},getEndOfChartMarkerText:function(){var t=this.chart,e=t.langFormat("accessibility.screenReaderSection.endOfChartMarker",{chart:t})
return'<div id="highcharts-end-of-chart-marker-'+t.index+'">'+e+"</div>"},onDataTableCreated:function(t){var e=this.chart
if(e.options.accessibility.enabled){this.viewDataTableButton&&this.viewDataTableButton.setAttribute("aria-expanded","true")
var i=t.tree.attributes||{}
i.tabindex=-1
i.summary=e.langFormat("accessibility.table.tableSummary",{chart:e})
t.tree.attributes=i}},focusDataTable:function(){var t=this.dataTableDiv;(t=t&&t.getElementsByTagName("table")[0])&&t.focus&&t.focus()},initSonifyButton:function(t){var e=this,i=this.sonifyButton=y(t),n=this.chart,o=function(t){null==i||i.setAttribute("aria-hidden","true")
null==i||i.setAttribute("aria-label","")
t.preventDefault()
t.stopPropagation()
t=n.langFormat("accessibility.sonification.playAsSoundClickAnnouncement",{chart:n})
e.announcer.announce(t)
setTimeout((function(){null==i||i.removeAttribute("aria-hidden")
null==i||i.removeAttribute("aria-label")
n.sonify&&n.sonify()}),1e3)}
i&&n&&(x(i,{tabindex:"-1"}),i.onclick=function(t){var e;((null===(e=n.options.accessibility)||void 0===e?void 0:e.screenReaderSection.onPlayAsSoundClick)||o).call(this,t,n)})},initDataTableButton:function(t){var e=this.viewDataTableButton=y(t),i=this.chart
t=t.replace("hc-linkto-","")
e&&(x(e,{tabindex:"-1","aria-expanded":!!y(t)}),e.onclick=i.options.accessibility.screenReaderSection.onViewDataTableClick||function(){i.viewData()})},getAxesDescription:function(){var t=this.chart,e=function(e,i){return 1<(e=t[e]).length||e[0]&&h(e[0].options.accessibility&&e[0].options.accessibility.enabled,i)},i=!!t.types&&0>t.types.indexOf("map"),n=!!t.hasCartesianSeries,o=e("xAxis",!t.angular&&n&&i)
e=e("yAxis",n&&i)
i={}
o&&(i.xAxis=this.getAxisDescriptionText("xAxis"))
e&&(i.yAxis=this.getAxisDescriptionText("yAxis"))
return i},getAxisDescriptionText:function(t){var e=this.chart,i=e[t]
return e.langFormat("accessibility.axis."+t+"Description"+(1<i.length?"Plural":"Singular"),{chart:e,names:i.map((function(t){return p(t)})),ranges:i.map((function(t){return m(t)})),numAxes:i.length})},destroy:function(){var t
null===(t=this.announcer)||void 0===t||t.destroy()}})
return i}))
e(t,"Accessibility/Components/ContainerComponent.js",[t["Accessibility/AccessibilityComponent.js"],t["Accessibility/Utils/ChartUtilities.js"],t["Core/Globals.js"],t["Accessibility/Utils/HTMLUtilities.js"],t["Core/Utilities.js"]],(function(t,e,i,n,o){var r=e.unhideChartElementFromAT,s=e.getChartTitle,a=i.doc,l=n.stripHTMLTagsFromString
e=o.extend;(i=function(){}).prototype=new t
e(i.prototype,{onChartUpdate:function(){this.handleSVGTitleElement()
this.setSVGContainerLabel()
this.setGraphicContainerAttrs()
this.setRenderToAttrs()
this.makeCreditsAccessible()},handleSVGTitleElement:function(){var t=this.chart,e="highcharts-title-"+t.index,i=l(t.langFormat("accessibility.svgContainerTitle",{chartTitle:s(t)}))
if(i.length){var n=this.svgTitleElement=this.svgTitleElement||a.createElementNS("http://www.w3.org/2000/svg","title")
n.textContent=i
n.id=e
t.renderTo.insertBefore(n,t.renderTo.firstChild)}},setSVGContainerLabel:function(){var t=this.chart,e=t.langFormat("accessibility.svgContainerLabel",{chartTitle:s(t)})
t.renderer.box&&e.length&&t.renderer.box.setAttribute("aria-label",e)},setGraphicContainerAttrs:function(){var t=this.chart,e=t.langFormat("accessibility.graphicContainerLabel",{chartTitle:s(t)})
e.length&&t.container.setAttribute("aria-label",e)},setRenderToAttrs:function(){var t=this.chart
"disabled"!==t.options.accessibility.landmarkVerbosity?t.renderTo.setAttribute("role","region"):t.renderTo.removeAttribute("role")
t.renderTo.setAttribute("aria-label",t.langFormat("accessibility.chartContainerLabel",{title:s(t),chart:t}))},makeCreditsAccessible:function(){var t=this.chart,e=t.credits
e&&(e.textStr&&e.element.setAttribute("aria-label",t.langFormat("accessibility.credits",{creditsStr:l(e.textStr)})),r(t,e.element))},destroy:function(){this.chart.renderTo.setAttribute("aria-hidden",!0)}})
return i}))
e(t,"Accessibility/HighContrastMode.js",[t["Core/Globals.js"]],(function(t){var e=t.doc,i=t.isMS,n=t.win
return{isHighContrastModeActive:function(){var t=/(Edg)/.test(n.navigator.userAgent)
if(n.matchMedia&&t)return n.matchMedia("(-ms-high-contrast: active)").matches
if(i&&n.getComputedStyle){(t=e.createElement("div")).style.backgroundImage="url(data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==)"
e.body.appendChild(t)
var o=(t.currentStyle||n.getComputedStyle(t)).backgroundImage
e.body.removeChild(t)
return"none"===o}return!1},setHighContrastTheme:function(t){t.highContrastModeActive=!0
var e=t.options.accessibility.highContrastTheme
t.update(e,!1)
t.series.forEach((function(t){var i=e.plotOptions[t.type]||{}
t.update({color:i.color||"windowText",colors:[i.color||"windowText"],borderColor:i.borderColor||"window"})
t.points.forEach((function(t){t.options&&t.options.color&&t.update({color:i.color||"windowText",borderColor:i.borderColor||"window"},!1)}))}))
t.redraw()}}}))
e(t,"Accessibility/HighContrastTheme.js",[],(function(){return{chart:{backgroundColor:"window"},title:{style:{color:"windowText"}},subtitle:{style:{color:"windowText"}},colorAxis:{minColor:"windowText",maxColor:"windowText",stops:[]},colors:["windowText"],xAxis:{gridLineColor:"windowText",labels:{style:{color:"windowText"}},lineColor:"windowText",minorGridLineColor:"windowText",tickColor:"windowText",title:{style:{color:"windowText"}}},yAxis:{gridLineColor:"windowText",labels:{style:{color:"windowText"}},lineColor:"windowText",minorGridLineColor:"windowText",tickColor:"windowText",title:{style:{color:"windowText"}}},tooltip:{backgroundColor:"window",borderColor:"windowText",style:{color:"windowText"}},plotOptions:{series:{lineColor:"windowText",fillColor:"window",borderColor:"windowText",edgeColor:"windowText",borderWidth:1,dataLabels:{connectorColor:"windowText",color:"windowText",style:{color:"windowText",textOutline:"none"}},marker:{lineColor:"windowText",fillColor:"windowText"}},pie:{color:"window",colors:["window"],borderColor:"windowText",borderWidth:1},boxplot:{fillColor:"window"},candlestick:{lineColor:"windowText",fillColor:"window"},errorbar:{fillColor:"window"}},legend:{backgroundColor:"window",itemStyle:{color:"windowText"},itemHoverStyle:{color:"windowText"},itemHiddenStyle:{color:"#555"},title:{style:{color:"windowText"}}},credits:{style:{color:"windowText"}},labels:{style:{color:"windowText"}},drilldown:{activeAxisLabelStyle:{color:"windowText"},activeDataLabelStyle:{color:"windowText"}},navigation:{buttonOptions:{symbolStroke:"windowText",theme:{fill:"window"}}},rangeSelector:{buttonTheme:{fill:"window",stroke:"windowText",style:{color:"windowText"},states:{hover:{fill:"window",stroke:"windowText",style:{color:"windowText"}},select:{fill:"#444",stroke:"windowText",style:{color:"windowText"}}}},inputBoxBorderColor:"windowText",inputStyle:{backgroundColor:"window",color:"windowText"},labelStyle:{color:"windowText"}},navigator:{handles:{backgroundColor:"window",borderColor:"windowText"},outlineColor:"windowText",maskFill:"transparent",series:{color:"windowText",lineColor:"windowText"},xAxis:{gridLineColor:"windowText"}},scrollbar:{barBackgroundColor:"#444",barBorderColor:"windowText",buttonArrowColor:"windowText",buttonBackgroundColor:"window",buttonBorderColor:"windowText",rifleColor:"windowText",trackBackgroundColor:"window",trackBorderColor:"windowText"}}}))
e(t,"Accessibility/Options/Options.js",[t["Core/Color/Palette.js"]],(function(t){return{accessibility:{enabled:!0,screenReaderSection:{beforeChartFormat:"<{headingTagName}>{chartTitle}</{headingTagName}><div>{typeDescription}</div><div>{chartSubtitle}</div><div>{chartLongdesc}</div><div>{playAsSoundButton}</div><div>{viewTableButton}</div><div>{xAxisDescription}</div><div>{yAxisDescription}</div><div>{annotationsTitle}{annotationsList}</div>",afterChartFormat:"{endOfChartMarker}",axisRangeDateFormat:"%Y-%m-%d %H:%M:%S"},series:{describeSingleSeries:!1,pointDescriptionEnabledThreshold:200},point:{valueDescriptionFormat:"{index}. {xDescription}{separator}{value}."},landmarkVerbosity:"all",linkedDescription:'*[data-highcharts-chart="{index}"] + .highcharts-description',keyboardNavigation:{enabled:!0,focusBorder:{enabled:!0,hideBrowserFocusOutline:!0,style:{color:t.highlightColor80,lineWidth:2,borderRadius:3},margin:2},order:["series","zoom","rangeSelector","legend","chartMenu"],wrapAround:!0,seriesNavigation:{skipNullPoints:!0,pointNavigationEnabledThreshold:!1}},announceNewData:{enabled:!1,minAnnounceInterval:5e3,interruptUser:!1}},legend:{accessibility:{enabled:!0,keyboardNavigation:{enabled:!0}}},exporting:{accessibility:{enabled:!0}}}}))
e(t,"Accessibility/Options/LangOptions.js",[],(function(){return{accessibility:{defaultChartTitle:"Chart",chartContainerLabel:"{title}. Highcharts interactive chart.",svgContainerLabel:"Interactive chart",drillUpButton:"{buttonText}",credits:"Chart credits: {creditsStr}",thousandsSep:",",svgContainerTitle:"",graphicContainerLabel:"",screenReaderSection:{beforeRegionLabel:"Chart screen reader information.",afterRegionLabel:"",annotations:{heading:"Chart annotations summary",descriptionSinglePoint:"{annotationText}. Related to {annotationPoint}",descriptionMultiplePoints:"{annotationText}. Related to {annotationPoint}{ Also related to, #each(additionalAnnotationPoints)}",descriptionNoPoints:"{annotationText}"},endOfChartMarker:"End of interactive chart."},sonification:{playAsSoundButtonText:"Play as sound, {chartTitle}",playAsSoundClickAnnouncement:"Play"},legend:{legendLabelNoTitle:"Toggle series visibility",legendLabel:"Chart legend: {legendTitle}",legendItem:"Show {itemName}"},zoom:{mapZoomIn:"Zoom chart",mapZoomOut:"Zoom out chart",resetZoomButton:"Reset zoom"},rangeSelector:{dropdownLabel:"{rangeTitle}",minInputLabel:"Select start date.",maxInputLabel:"Select end date.",clickButtonAnnouncement:"Viewing {axisRangeDescription}"},table:{viewAsDataTableButtonText:"View as data table, {chartTitle}",tableSummary:"Table representation of chart."},announceNewData:{newDataAnnounce:"Updated data for chart {chartTitle}",newSeriesAnnounceSingle:"New data series: {seriesDesc}",newPointAnnounceSingle:"New data point: {pointDesc}",newSeriesAnnounceMultiple:"New data series in chart {chartTitle}: {seriesDesc}",newPointAnnounceMultiple:"New data point in chart {chartTitle}: {pointDesc}"},seriesTypeDescriptions:{boxplot:"Box plot charts are typically used to display groups of statistical data. Each data point in the chart can have up to 5 values: minimum, lower quartile, median, upper quartile, and maximum.",arearange:"Arearange charts are line charts displaying a range between a lower and higher value for each point.",areasplinerange:"These charts are line charts displaying a range between a lower and higher value for each point.",bubble:"Bubble charts are scatter charts where each data point also has a size value.",columnrange:"Columnrange charts are column charts displaying a range between a lower and higher value for each point.",errorbar:"Errorbar series are used to display the variability of the data.",funnel:"Funnel charts are used to display reduction of data in stages.",pyramid:"Pyramid charts consist of a single pyramid with item heights corresponding to each point value.",waterfall:"A waterfall chart is a column chart where each column contributes towards a total end value."},chartTypes:{emptyChart:"Empty chart",mapTypeDescription:"Map of {mapTitle} with {numSeries} data series.",unknownMap:"Map of unspecified region with {numSeries} data series.",combinationChart:"Combination chart with {numSeries} data series.",defaultSingle:"Chart with {numPoints} data {#plural(numPoints, points, point)}.",defaultMultiple:"Chart with {numSeries} data series.",splineSingle:"Line chart with {numPoints} data {#plural(numPoints, points, point)}.",splineMultiple:"Line chart with {numSeries} lines.",lineSingle:"Line chart with {numPoints} data {#plural(numPoints, points, point)}.",lineMultiple:"Line chart with {numSeries} lines.",columnSingle:"Bar chart with {numPoints} {#plural(numPoints, bars, bar)}.",columnMultiple:"Bar chart with {numSeries} data series.",barSingle:"Bar chart with {numPoints} {#plural(numPoints, bars, bar)}.",barMultiple:"Bar chart with {numSeries} data series.",pieSingle:"Pie chart with {numPoints} {#plural(numPoints, slices, slice)}.",pieMultiple:"Pie chart with {numSeries} pies.",scatterSingle:"Scatter chart with {numPoints} {#plural(numPoints, points, point)}.",scatterMultiple:"Scatter chart with {numSeries} data series.",boxplotSingle:"Boxplot with {numPoints} {#plural(numPoints, boxes, box)}.",boxplotMultiple:"Boxplot with {numSeries} data series.",bubbleSingle:"Bubble chart with {numPoints} {#plural(numPoints, bubbles, bubble)}.",bubbleMultiple:"Bubble chart with {numSeries} data series."},axis:{xAxisDescriptionSingular:"The chart has 1 X axis displaying {names[0]}. {ranges[0]}",xAxisDescriptionPlural:"The chart has {numAxes} X axes displaying {#each(names, -1) }and {names[-1]}.",yAxisDescriptionSingular:"The chart has 1 Y axis displaying {names[0]}. {ranges[0]}",yAxisDescriptionPlural:"The chart has {numAxes} Y axes displaying {#each(names, -1) }and {names[-1]}.",timeRangeDays:"Range: {range} days.",timeRangeHours:"Range: {range} hours.",timeRangeMinutes:"Range: {range} minutes.",timeRangeSeconds:"Range: {range} seconds.",rangeFromTo:"Range: {rangeFrom} to {rangeTo}.",rangeCategories:"Range: {numCategories} categories."},exporting:{chartMenuLabel:"Chart menu",menuButtonLabel:"View chart menu",exportRegionLabel:"Chart menu"},series:{summary:{default:"{name}, series {ix} of {numSeries} with {numPoints} data {#plural(numPoints, points, point)}.",defaultCombination:"{name}, series {ix} of {numSeries} with {numPoints} data {#plural(numPoints, points, point)}.",line:"{name}, line {ix} of {numSeries} with {numPoints} data {#plural(numPoints, points, point)}.",lineCombination:"{name}, series {ix} of {numSeries}. Line with {numPoints} data {#plural(numPoints, points, point)}.",spline:"{name}, line {ix} of {numSeries} with {numPoints} data {#plural(numPoints, points, point)}.",splineCombination:"{name}, series {ix} of {numSeries}. Line with {numPoints} data {#plural(numPoints, points, point)}.",column:"{name}, bar series {ix} of {numSeries} with {numPoints} {#plural(numPoints, bars, bar)}.",columnCombination:"{name}, series {ix} of {numSeries}. Bar series with {numPoints} {#plural(numPoints, bars, bar)}.",bar:"{name}, bar series {ix} of {numSeries} with {numPoints} {#plural(numPoints, bars, bar)}.",barCombination:"{name}, series {ix} of {numSeries}. Bar series with {numPoints} {#plural(numPoints, bars, bar)}.",pie:"{name}, pie {ix} of {numSeries} with {numPoints} {#plural(numPoints, slices, slice)}.",pieCombination:"{name}, series {ix} of {numSeries}. Pie with {numPoints} {#plural(numPoints, slices, slice)}.",scatter:"{name}, scatter plot {ix} of {numSeries} with {numPoints} {#plural(numPoints, points, point)}.",scatterCombination:"{name}, series {ix} of {numSeries}, scatter plot with {numPoints} {#plural(numPoints, points, point)}.",boxplot:"{name}, boxplot {ix} of {numSeries} with {numPoints} {#plural(numPoints, boxes, box)}.",boxplotCombination:"{name}, series {ix} of {numSeries}. Boxplot with {numPoints} {#plural(numPoints, boxes, box)}.",bubble:"{name}, bubble series {ix} of {numSeries} with {numPoints} {#plural(numPoints, bubbles, bubble)}.",bubbleCombination:"{name}, series {ix} of {numSeries}. Bubble series with {numPoints} {#plural(numPoints, bubbles, bubble)}.",map:"{name}, map {ix} of {numSeries} with {numPoints} {#plural(numPoints, areas, area)}.",mapCombination:"{name}, series {ix} of {numSeries}. Map with {numPoints} {#plural(numPoints, areas, area)}.",mapline:"{name}, line {ix} of {numSeries} with {numPoints} data {#plural(numPoints, points, point)}.",maplineCombination:"{name}, series {ix} of {numSeries}. Line with {numPoints} data {#plural(numPoints, points, point)}.",mapbubble:"{name}, bubble series {ix} of {numSeries} with {numPoints} {#plural(numPoints, bubbles, bubble)}.",mapbubbleCombination:"{name}, series {ix} of {numSeries}. Bubble series with {numPoints} {#plural(numPoints, bubbles, bubble)}."},description:"{description}",xAxisDescription:"X axis, {name}",yAxisDescription:"Y axis, {name}",nullPointValue:"No value",pointAnnotationsDescription:"{Annotation: #each(annotations). }"}}}}))
e(t,"Accessibility/Options/DeprecatedOptions.js",[t["Core/Utilities.js"]],(function(t){function e(t,e,i){for(var n,r=0;r<e.length-1;++r)t=t[n=e[r]]=o(t[n],{})
t[e[e.length-1]]=i}function i(t,i,o,r){function s(t,e){return e.reduce((function(t,e){return t[e]}),t)}var a=s(t.options,i),l=s(t.options,o)
Object.keys(r).forEach((function(s){var c,u=a[s]
void 0!==u&&(e(l,r[s],u),n(32,!1,t,((c={})[i.join(".")+"."+s]=o.join(".")+"."+r[s].join("."),c)))}))}var n=t.error,o=t.pick
return function(t){!function(t){var e=t.options.chart||{},i=t.options.accessibility||{};["description","typeDescription"].forEach((function(o){var r
e[o]&&(i[o]=e[o],n(32,!1,t,((r={})["chart."+o]="use accessibility."+o,r)))}))}(t)
!function(t){t.axes.forEach((function(e){(e=e.options)&&e.description&&(e.accessibility=e.accessibility||{},e.accessibility.description=e.description,n(32,!1,t,{"axis.description":"use axis.accessibility.description"}))}))}(t)
t.series&&function(t){var i={description:["accessibility","description"],exposeElementToA11y:["accessibility","exposeAsGroupOnly"],pointDescriptionFormatter:["accessibility","pointDescriptionFormatter"],skipKeyboardNavigation:["accessibility","keyboardNavigation","enabled"]}
t.series.forEach((function(o){Object.keys(i).forEach((function(r){var s,a=o.options[r]
void 0!==a&&(e(o.options,i[r],"skipKeyboardNavigation"===r?!a:a),n(32,!1,t,((s={})["series."+r]="series."+i[r].join("."),s)))}))}))}(t)
i(t,["accessibility"],["accessibility"],{pointDateFormat:["point","dateFormat"],pointDateFormatter:["point","dateFormatter"],pointDescriptionFormatter:["point","descriptionFormatter"],pointDescriptionThreshold:["series","pointDescriptionEnabledThreshold"],pointNavigationThreshold:["keyboardNavigation","seriesNavigation","pointNavigationEnabledThreshold"],pointValueDecimals:["point","valueDecimals"],pointValuePrefix:["point","valuePrefix"],pointValueSuffix:["point","valueSuffix"],screenReaderSectionFormatter:["screenReaderSection","beforeChartFormatter"],describeSingleSeries:["series","describeSingleSeries"],seriesDescriptionFormatter:["series","descriptionFormatter"],onTableAnchorClick:["screenReaderSection","onViewDataTableClick"],axisRangeDateFormat:["screenReaderSection","axisRangeDateFormat"]})
i(t,["accessibility","keyboardNavigation"],["accessibility","keyboardNavigation","seriesNavigation"],{skipNullPoints:["skipNullPoints"],mode:["mode"]})
i(t,["lang","accessibility"],["lang","accessibility"],{legendItem:["legend","legendItem"],legendLabel:["legend","legendLabel"],mapZoomIn:["zoom","mapZoomIn"],mapZoomOut:["zoom","mapZoomOut"],resetZoomButton:["zoom","resetZoomButton"],screenReaderRegionLabel:["screenReaderSection","beforeRegionLabel"],rangeSelectorButton:["rangeSelector","buttonText"],rangeSelectorMaxInput:["rangeSelector","maxInputLabel"],rangeSelectorMinInput:["rangeSelector","minInputLabel"],svgContainerEnd:["screenReaderSection","endOfChartMarker"],viewAsDataTable:["table","viewAsDataTableButtonText"],tableSummary:["table","tableSummary"]})}}))
e(t,"Accessibility/A11yI18n.js",[t["Core/Globals.js"],t["Core/Utilities.js"]],(function(t,e){var i=e.format,n=e.pick
t.i18nFormat=function(t,e,o){var r=function(t,e){var i=(t=t.slice(e||0)).indexOf("{"),n=t.indexOf("}")
if(-1<i&&n>i)return{statement:t.substring(i+1,n),begin:e+i+1,end:e+n}},s=[],a=0
do{var l=r(t,a),c=t.substring(a,l&&l.begin-1)
c.length&&s.push({value:c,type:"constant"})
l&&s.push({value:l.statement,type:"statement"})
a=l?l.end+1:a+1}while(l)
s.forEach((function(t){"statement"===t.type&&(t.value=function(t,e){var i=t.indexOf("#each("),o=t.indexOf("#plural("),r=t.indexOf("["),s=t.indexOf("]")
if(-1<i){r=t.slice(i).indexOf(")")+i
var a=t.substring(0,i)
o=t.substring(r+1)
r=t.substring(i+6,r).split(",")
i=Number(r[1])
t=""
if(e=e[r[0]])for(i=0>(i=isNaN(i)?e.length:i)?e.length+i:Math.min(i,e.length),r=0;r<i;++r)t+=a+e[r]+o
return t.length?t:""}if(-1<o){a=t.slice(o).indexOf(")")+o
t=t.substring(o+8,a).split(",")
switch(Number(e[t[0]])){case 0:t=n(t[4],t[1])
break
case 1:t=n(t[2],t[1])
break
case 2:t=n(t[3],t[1])
break
default:t=t[1]}return e=t?(e=t).trim&&e.trim()||e.replace(/^\s+|\s+$/g,""):""}return-1<r?(o=t.substring(0,r),t=Number(t.substring(r+1,s)),e=e[o],!isNaN(t)&&e&&(0>t?void 0===(a=e[e.length+t])&&(a=e[0]):void 0===(a=e[t])&&(a=e[e.length-1])),void 0!==a?a:""):"{"+t+"}"}(t.value,e))}))
return i(s.reduce((function(t,e){return t+e.value}),""),e,o)}
t.Chart.prototype.langFormat=function(e,i){e=e.split(".")
for(var n=this.options.lang,o=0;o<e.length;++o)n=n&&n[e[o]]
return"string"==typeof n?t.i18nFormat(n,i,this):""}}))
e(t,"Accessibility/FocusBorder.js",[t["Core/Globals.js"],t["Core/Renderer/SVG/SVGElement.js"],t["Core/Renderer/SVG/SVGLabel.js"],t["Core/Utilities.js"]],(function(t,e,i,n){function o(t){for(var e=[],i=1;i<arguments.length;i++)e[i-1]=arguments[i]
t.focusBorderUpdateHooks||(t.focusBorderUpdateHooks={},l.forEach((function(i){var n=t[i+="Setter"]||t._defaultSetter
t.focusBorderUpdateHooks[i]=n
t[i]=function(){var i=n.apply(t,arguments)
t.addFocusBorder.apply(t,e)
return i}})))}var r=n.addEvent,s=n.extend,a=n.pick,l="x y transform width height r d stroke-width".split(" ")
s(e.prototype,{addFocusBorder:function(e,n){this.focusBorder&&this.removeFocusBorder()
var r=this.getBBox(),s=a(e,3)
r.x+=this.translateX?this.translateX:0
r.y+=this.translateY?this.translateY:0
var l=r.x-s,c=r.y-s,u=r.width+2*s,h=r.height+2*s,d=this instanceof i
if("text"===this.element.nodeName||d){var p=!!this.rotation
if(d)var m={x:p?1:0,y:0}
else{var g=m=0
"middle"===this.attr("text-anchor")?(m=t.isFirefox&&this.rotation?.25:.5,g=t.isFirefox&&!this.rotation?.75:.5):this.rotation?m=.25:g=.75
m={x:m,y:g}}g=+this.attr("x")
var f=+this.attr("y")
isNaN(g)||(l=g-r.width*m.x-s)
isNaN(f)||(c=f-r.height*m.y-s)
d&&p&&(d=u,u=h,h=d,isNaN(g)||(l=g-r.height*m.x-s),isNaN(f)||(c=f-r.width*m.y-s))}this.focusBorder=this.renderer.rect(l,c,u,h,parseInt((n&&n.borderRadius||0).toString(),10)).addClass("highcharts-focus-border").attr({zIndex:99}).add(this.parentGroup)
this.renderer.styledMode||this.focusBorder.attr({stroke:n&&n.stroke,"stroke-width":n&&n.strokeWidth})
o(this,e,n)
!function(t){if(!t.focusBorderDestroyHook){var e=t.destroy
t.destroy=function(){var i,n
null===(n=null===(i=t.focusBorder)||void 0===i?void 0:i.destroy)||void 0===n||n.call(i)
return e.apply(t,arguments)}
t.focusBorderDestroyHook=e}}(this)},removeFocusBorder:function(){(t=this).focusBorderUpdateHooks&&(Object.keys(t.focusBorderUpdateHooks).forEach((function(e){var i=t.focusBorderUpdateHooks[e]
i===t._defaultSetter?delete t[e]:t[e]=i})),delete t.focusBorderUpdateHooks)
var t
this.focusBorderDestroyHook&&(this.destroy=this.focusBorderDestroyHook,delete this.focusBorderDestroyHook)
this.focusBorder&&(this.focusBorder.destroy(),delete this.focusBorder)}})
t.Chart.prototype.renderFocusBorder=function(){var t=this.focusElement,e=this.options.accessibility.keyboardNavigation.focusBorder
t&&(t.removeFocusBorder(),e.enabled&&t.addFocusBorder(e.margin,{stroke:e.style.color,strokeWidth:e.style.lineWidth,borderRadius:e.style.borderRadius}))}
t.Chart.prototype.setFocusToElement=function(t,e){var i=this.options.accessibility.keyboardNavigation.focusBorder;(e=e||t.element)&&e.focus&&(e.hcEvents&&e.hcEvents.focusin||r(e,"focusin",(function(){})),e.focus(),i.hideBrowserFocusOutline&&(e.style.outline="none"))
this.focusElement&&this.focusElement.removeFocusBorder()
this.focusElement=t
this.renderFocusBorder()}}))
e(t,"Accessibility/Accessibility.js",[t["Accessibility/Utils/ChartUtilities.js"],t["Core/Globals.js"],t["Accessibility/KeyboardNavigationHandler.js"],t["Core/Options.js"],t["Core/Series/Point.js"],t["Core/Series/Series.js"],t["Core/Utilities.js"],t["Accessibility/AccessibilityComponent.js"],t["Accessibility/KeyboardNavigation.js"],t["Accessibility/Components/LegendComponent.js"],t["Accessibility/Components/MenuComponent.js"],t["Accessibility/Components/SeriesComponent/SeriesComponent.js"],t["Accessibility/Components/ZoomComponent.js"],t["Accessibility/Components/RangeSelectorComponent.js"],t["Accessibility/Components/InfoRegionsComponent.js"],t["Accessibility/Components/ContainerComponent.js"],t["Accessibility/HighContrastMode.js"],t["Accessibility/HighContrastTheme.js"],t["Accessibility/Options/Options.js"],t["Accessibility/Options/LangOptions.js"],t["Accessibility/Options/DeprecatedOptions.js"],t["Accessibility/Utils/HTMLUtilities.js"]],(function(t,e,i,n,o,r,s,a,l,c,u,h,d,p,m,g,f,b,y,v,x,A){function w(t){this.init(t)}var C=e.doc,T=s.addEvent,E=s.extend,S=s.fireEvent,P=s.merge
P(!0,n.defaultOptions,y,{accessibility:{highContrastTheme:b},lang:v})
e.A11yChartUtilities=t
e.A11yHTMLUtilities=A
e.KeyboardNavigationHandler=i
e.AccessibilityComponent=a
w.prototype={init:function(t){this.chart=t
C.addEventListener&&t.renderer.isSVG?(x(t),this.initComponents(),this.keyboardNavigation=new l(t,this.components),this.update()):t.renderTo.setAttribute("aria-hidden",!0)},initComponents:function(){var t=this.chart,e=t.options.accessibility
this.components={container:new g,infoRegions:new m,legend:new c,chartMenu:new u,rangeSelector:new p,series:new h,zoom:new d}
e.customComponents&&E(this.components,e.customComponents)
var i=this.components
this.getComponentOrder().forEach((function(e){i[e].initBase(t)
i[e].init()}))},getComponentOrder:function(){if(!this.components)return[]
if(!this.components.series)return Object.keys(this.components)
var t=Object.keys(this.components).filter((function(t){return"series"!==t}))
return["series"].concat(t)},update:function(){var t=this.components,e=this.chart,i=e.options.accessibility
S(e,"beforeA11yUpdate")
e.types=this.getChartTypes()
this.getComponentOrder().forEach((function(i){t[i].onChartUpdate()
S(e,"afterA11yComponentUpdate",{name:i,component:t[i]})}))
this.keyboardNavigation.update(i.keyboardNavigation.order)
!e.highContrastModeActive&&f.isHighContrastModeActive()&&f.setHighContrastTheme(e)
S(e,"afterA11yUpdate",{accessibility:this})},destroy:function(){var t=this.chart||{},e=this.components
Object.keys(e).forEach((function(t){e[t].destroy()
e[t].destroyBase()}))
this.keyboardNavigation&&this.keyboardNavigation.destroy()
t.renderTo&&t.renderTo.setAttribute("aria-hidden",!0)
t.focusElement&&t.focusElement.removeFocusBorder()},getChartTypes:function(){var t={}
this.chart.series.forEach((function(e){t[e.type]=1}))
return Object.keys(t)}}
e.Chart.prototype.updateA11yEnabled=function(){var t=this.accessibility,e=this.options.accessibility
e&&e.enabled?t?t.update():this.accessibility=new w(this):t?(t.destroy&&t.destroy(),delete this.accessibility):this.renderTo.setAttribute("aria-hidden",!0)}
T(e.Chart,"render",(function(t){this.a11yDirty&&this.renderTo&&(delete this.a11yDirty,this.updateA11yEnabled())
var e=this.accessibility
e&&e.getComponentOrder().forEach((function(t){e.components[t].onChartRender()}))}))
T(e.Chart,"update",(function(t){(t=t.options.accessibility)&&(t.customComponents&&(this.options.accessibility.customComponents=t.customComponents,delete t.customComponents),P(!0,this.options.accessibility,t),this.accessibility&&this.accessibility.destroy&&(this.accessibility.destroy(),delete this.accessibility))
this.a11yDirty=!0}))
T(o,"update",(function(){this.series.chart.accessibility&&(this.series.chart.a11yDirty=!0)}));["addSeries","init"].forEach((function(t){T(e.Chart,t,(function(){this.a11yDirty=!0}))}));["update","updatedData","remove"].forEach((function(t){T(r,t,(function(){this.chart.accessibility&&(this.chart.a11yDirty=!0)}))}));["afterDrilldown","drillupall"].forEach((function(t){T(e.Chart,t,(function(){this.accessibility&&this.accessibility.update()}))}))
T(e.Chart,"destroy",(function(){this.accessibility&&this.accessibility.destroy()}))}))
e(t,"masters/modules/accessibility.src.js",[],(function(){}))}))

//# sourceMappingURL=accessibility.map