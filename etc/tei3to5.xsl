<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:tei="http://www.tei-c.org/ns/1.0"
                xmlns:exsl="http://exslt.org/common"
                xmlns:glam="urn:umich:lib:dor:model:2026:resource:glam"
                exclude-result-prefixes="xs exsl"
                version="1.0">
    <xsl:output method="xml" version="1.0" encoding="utf-8" indent="yes"/>

    <xsl:param name="idno" />
    <xsl:param name="encoding_level" select="//EDITORIALDECL/@N" />

    <xsl:variable name="uppercase" select="'ABCDEFGHIJKLMNOPQRSTUVWXYZ'"/>
    <xsl:variable name="lowercase" select="'abcdefghijklmnopqrstuvwxyz'"/>

    <xsl:variable name="mapping-tmp">
        <ol>
            <li p3="HEADER" p5="teiHeader" />
            <li p3="SOURCEDESC" p5="sourceDesc" />
            <li p3="PUBLICATIONSTMT" p5="publicationStmt" />
            <li p3="TITLESTMT" p5="titleStmt" />
            <li p3="FILEDESC" p5="fileDesc" />
            <li p3="BIBLSCOPE" p5="biblScope" />
            <li p3="BIBLFULL" p5="biblFull" />
            <li p3="NOTESSTMT" p5="notesStmt" />
            <li p3="ENCODINGDESC" p5="encodingDesc" />
            <li p3="PROJECTDESC" p5="projectDesc" />
            <li p3="LANGUSAGE" p5="langUsage" />
            <li p3="TEXTCLASS" p5="textClass" />
            <li p3="HI1" p5="hi" />
        </ol>
    </xsl:variable>
    <xsl:variable name="mapping" select="exsl:node-set($mapping-tmp)" />

    <xsl:template match="/">
        <tei:TEI xml:id="_{$idno}">
            <xsl:apply-templates select="//FullTextResults/ItemHeader/HEADER" mode="copy" />
            <xsl:apply-templates select="//FullTextResults/DocContent/DLPSTEXTCLASS/TEXT" mode="copy" />
        </tei:TEI>
    </xsl:template>

    <xsl:template match="HEADER" mode="xx">
        <xsl:variable name="tag-name">teiHeader</xsl:variable>
        <xsl:element name="tei:{$tag-name}">test</xsl:element>
    </xsl:template>

    <xsl:template match="P[PB[@REF]]" mode="copy" priority="101">
        <xsl:apply-templates select="PB" mode="copy" />
    </xsl:template>

    <xsl:template match="PB[@REF]" mode="copy" priority="101">
        <tei:pb facs="{@SEQ}" glam:seq="{@SEQ}" type="{@FTR}">
            <xsl:apply-templates select="@N" mode="copy" />
            <!-- <xsl:apply-templates select="@SEQ" mode="copy" />
            <xsl:apply-templates select="@FTR" mode="copy" /> -->
        </tei:pb> 
    </xsl:template>

    <xsl:template match="PB" mode="copy" priority="99">
        <tei:pb n="{@N}"></tei:pb>
    </xsl:template>

    <xsl:template match="node()[name()]" mode="copy">
        <xsl:variable name="p3" select="name()" />
        <xsl:variable name="p5">
            <xsl:choose>
                <xsl:when test="$mapping//li[@p3=$p3]">
                    <xsl:value-of select="$mapping//li[@p3=$p3]/@p5" />
                </xsl:when>
                <xsl:otherwise>
                    <xsl:value-of select="translate($p3, $uppercase, $lowercase)"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <!-- <xsl:message><xsl:value-of select="$p3" /> :: <xsl:value-of select="$p5" /></xsl:message> -->
        <xsl:element name="tei:{$p5}">
            <xsl:apply-templates select="@*" mode="copy" />
            <xsl:apply-templates select="*|text()" mode="copy" />
        </xsl:element>
    </xsl:template>

    <xsl:template match="@NODE" mode="copy" priority="101">
        <xsl:attribute name="glam:node">
            <xsl:value-of select="translate(., $uppercase, $lowercase)" />
        </xsl:attribute>
    </xsl:template>

    <xsl:template match="@ID" mode="copy" priority="101">
        <xsl:attribute name="xml:id">
            <xsl:value-of select="concat('_', .)" />
        </xsl:attribute>
    </xsl:template>

    <xsl:template match="@TARGET" mode="copy" priority="101">
        <xsl:attribute name="target">
            <xsl:value-of select="concat('_', .)" />
        </xsl:attribute>
    </xsl:template>

    <xsl:template match="@*" mode="copy">
        <xsl:variable name="p3" select="name()" />
        <xsl:variable name="p5" select="translate($p3, $uppercase, $lowercase)"/>
        <xsl:if test="normalize-space(.)">
            <xsl:attribute name="{$p5}">
                <xsl:value-of select="." />
            </xsl:attribute>
        </xsl:if>
    </xsl:template>

    <xsl:template match="text()" mode="copy">
        <xsl:copy>
        </xsl:copy>
    </xsl:template>
</xsl:stylesheet>