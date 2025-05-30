--- Kindle-style Status Bar Patch for KOReader
-- Transforms the footer into a left/right justified layout similar to Kindle devices.
-- Implements custom time remaining generators and handles dynamic spacing.
-- Developed & Tested on KOReader version 2025-05-22
-- @author Muaiyad H.
-- @version 1.0

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen
local _ = require("gettext")

local ReaderFooter = require("apps/reader/modules/readerfooter")

----------------------
-- Original methods --
----------------------
local original_init = ReaderFooter.init
local original_updateFooterText = ReaderFooter._updateFooterText
local original_getDataFromStatistics = ReaderFooter.getDataFromStatistics

-----------------------
-- Helper functions --
-----------------------
function splitBySeparator(self, text)
    local separator = self:genSeparator()
    local sep_start, sep_end = string.find(text, separator, 1, true)

    local left_text, right_text
    if sep_start then
        left_text = string.sub(text, 1, sep_start - 1)
        right_text = string.sub(text, sep_end + 1)
    elseif text ~= "" then -- No separator found, add progress automatically
        left_text = text
        right_text = self.textGeneratorMap.percentage(self)
    else -- No text found, return empty
        left_text = ""
        right_text = ""
    end

    return left_text, right_text
end

--------------
-- Patching --
--------------
function ReaderFooter:init()
    -- Update the "time left in book", "chapter", and "current page" text generator functions
    self.textGeneratorMap.book_time_to_read = function(footer)
        local left = footer.ui.document:getTotalPagesLeft(footer.pageno)
        return footer:getDataFromStatistics("", left, "Book")
    end

    self.textGeneratorMap.chapter_time_to_read = function(footer)
        local left = footer.ui.toc:getChapterPagesLeft(footer.pageno) or footer.ui.document:getTotalPagesLeft(footer.pageno)
        return footer:getDataFromStatistics("", left, "Chapter")
    end

    -- Same as the original function in ReaderFooter, only now we're using the format
    -- "Page N" or "Position N"
    self.textGeneratorMap.page_progress = function(footer)
        if footer.pageno then
            if footer.ui.pagemap and footer.ui.pagemap:wantsPageLabels() then
                -- (Page labels might not be numbers)
                return footer.ui.pagemap:getCurrentPageLabel(true)
            end
            if footer.ui.document:hasHiddenFlows() then
                -- i.e., if we are hiding non-linear fragments and there's anything to hide,
                local flow = footer.ui.document:getPageFlow(footer.pageno)
                local page = footer.ui.document:getPageNumberInFlow(footer.pageno)
                local pages = footer.ui.document:getTotalPagesInFlow(flow)
                if flow == 0 then
                    return ("Page %d"):format(page)
                else
                    return ("Page %d"):format(page)
                end
            else
                return ("Page %d"):format(footer.pageno)
            end
        elseif footer.position then
            return ("Position %d"):format(footer.position)
        end
    end

    -- Call the original init function to continue as normal
    return original_init(self)
end

function ReaderFooter:updateFooterContainer()
    -- Get the L/R margins from settings
    local margins = self.ui.document:getPageMargins()
    if not margins then
        margins = { left = 0, right = 0 } -- fallback
    end

    -- Create two new margin objects using the respective values
    self.left_margin_span = HorizontalSpan:new{ width = margins.left }
    self.right_margin_span = HorizontalSpan:new{ width = margins.right }

    -- This part is simplified from the original ReaderFooter:updateFooterContainer()
    -- <FROM READERFOOTER>
    self.vertical_frame = VerticalGroup:new{}
    if self.settings.bottom_horizontal_separator then
        self.separator_line = LineWidget:new{
            dimen = Geom:new{
                w = 0,
                h = Size.line.medium,
            }
        }
        local vertical_span = VerticalSpan:new{width = Size.span.vertical_default}
        table.insert(self.vertical_frame, self.separator_line)
        table.insert(self.vertical_frame, vertical_span)
    end
    -- </FROM READERFOOTER>

    -- Get the footer text and split it to be assigned for the left/right containers
    local text = self.text_container[1].text
    local left_text, right_text = splitBySeparator(self, text)

    -- Create separate left/right text containers
    self.left_text_widget = TextWidget:new{
        text = left_text,
        face = self.footer_text_face,
        bold = self.settings.text_font_bold,
    }

    self.right_text_widget = TextWidget:new{
        text = right_text,
        face = self.footer_text_face,
        bold = self.settings.text_font_bold,
    }

    self.left_text_container = LeftContainer:new{
        dimen = Geom:new{ w = 0, h = self.height },
        self.left_text_widget,
    }

    self.right_text_container = RightContainer:new{
        dimen = Geom:new{ w = 0, h = self.height },
        self.right_text_widget,
    }

    -- Calculate dimensions and spacing
    local left_width = left_text ~= "" and self.left_text_widget:getSize().w or 0
    local right_width = right_text ~= "" and self.right_text_widget:getSize().w or 0
    self.left_text_container.dimen.w = left_width
    self.right_text_container.dimen.w = right_width

    -- Calculate dynamic spacer width
    local available_width = Screen:getWidth() - margins.left - margins.right
    local spacer_width = math.max(0, available_width - left_width - right_width) -- Minimum size of 0 pixels

    -- Create dynamic spacer object
    self.dynamic_spacer = HorizontalSpan:new{ width = spacer_width }

    -- Add all objects in this order:
    -- L margin, L text, EMPTY SPACE, R text, R margin
    self.horizontal_group = HorizontalGroup:new{
        self.left_margin_span,
        self.left_text_container,
        self.dynamic_spacer,
        self.right_text_container,
        self.right_margin_span,
    }

    -- This part is also simplified from the original ReaderFooter:updateFooterContainer
    -- <FROM READERFOOTER>
    self.footer_container = LeftContainer:new{
        dimen = Geom:new{ w = 0, h = self.height },
        self.horizontal_group
    }

    local vertical_span = VerticalSpan:new{width = Size.span.vertical_default}

    table.insert(self.vertical_frame, self.footer_container)
    self.footer_content = FrameContainer:new{
        self.vertical_frame,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }

    self.footer_positioner = BottomContainer:new{
        dimen = Geom:new(),
        self.footer_content,
    }
    self[1] = self.footer_positioner
    -- </FROM READERFOOTER>
end

function ReaderFooter:_updateFooterText(force_repaint, full_repaint)
    -- This portion is directly from ReaderFooter, as the patch needs updated text
    -- and this way is slightly more efficient than calling "_updateFooterText" twice.
    -- <FROM READERFOOTER>
    -- footer is invisible, we need neither a repaint nor a recompute, go away.
    if not self.view.footer_visible and not force_repaint and not full_repaint then
        return
    end

    local text = self:genFooterText() or ""
    for _, v in ipairs(self.additional_footer_content) do
        local value = v()
        if value and value ~= "" then
            text = text == "" and value or value .. self:genSeparator() .. text
        end
    end
    -- </FROM READERFOOTER>

    local left_text, right_text = splitBySeparator(self, text)

    -- Only update the widgets if they exist (after init stuff)
    if self.left_text_widget then
        self.left_text_widget:setText(left_text)
        self.right_text_widget:setText(right_text)
    end

    -- Update margins in case they changed (user changed the L/R margins settings)
    local margins = self.ui.document:getPageMargins()
    if not margins then
        margins = { left = 0, right = 0 } -- fallback
    end
    local original_margins = self.left_margin_span.width + self.right_margin_span.width
    local new_margins = margins.left + margins.right
    self.dynamic_spacer.width = self.dynamic_spacer.width + original_margins - new_margins
    self.left_margin_span.width = margins.left
    self.right_margin_span.width = margins.right

    -- Call original function AFTER updating the left/right text widgets and margins
    original_updateFooterText(self, force_repaint, full_repaint)
end


--- Generates time remaining text with proper formatting
-- @param title string (unused in patched version. Kept for compatibility)
-- @param pages number Number of remaining pages.
-- @param document_type string "Chapter" or "Book" or similar. Used in output format
-- @return string Formatted time string ("X mins left in document") or "Document complete" if no remaining pages
function ReaderFooter:getDataFromStatistics(title, pages, document_type)

    -- Fall back to original method if no document_type specified, meaning it's called from
    -- other, unmodified KOReader functions.
    if not document_type then
        return original_getDataFromStatistics(self, title, pages)
    end

    -- No remaining pages. Return "X complete"
    if pages == 0 then return string.format("%s\u{00a0}complete", document_type) end

    local lower_document_type = string.lower(document_type)

    local sec = _("N/A") -- Fallback if no reading statistics available
    local average_time_per_page = self:getAvgTimePerPage()
    if average_time_per_page then
        local needed_time = pages * average_time_per_page  -- in seconds
        local hrs = math.floor(needed_time / 3600)
        local mins = math.max(math.floor(needed_time / 60) - hrs*60, 1) -- minimum 1 minute display
        if hrs > 0 then
            local hrs_txt = "hrs"
            if hrs == 1 then hrs_txt = "hr" end
            local mins_txt = "mins"
            if mins == 1 then mins_txt = "min" end
            sec = string.format("%d %s %d %s left in %s", hrs, hrs_txt, mins, mins_txt, lower_document_type)
        else
            local mins_txt = "mins"
            if mins == 1 then mins_txt = "min" end
            sec = string.format("%d %s left in %s", mins, mins_txt, lower_document_type)
        end
    end
    -- Replace spaces with non-breaking spaces as KOReader doesn't modify those
    -- Otherwise, they'll get squished
    sec = sec:gsub(" ", "\u{00a0}")
    return sec
end
